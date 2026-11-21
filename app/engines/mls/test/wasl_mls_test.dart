/// اختبارات نواة MLS (المرحلة 21 — 1.19.0): التقارب على كل الأعضاء عند كل
/// كومت، إثبات تكلفة log₂(N) على شجرة سعة 512 (أكثر من 256)، سرية أمامية
/// للمنضم، إقصاء المزال، سلاسل الأجيال، رفض التوقيع المغاير والمتأخر،
/// وبوابة التوافق مع التشفير الحالي (فصل علامات wasl-mls عن wasl-dr).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:wasl_mls/wasl_mls.dart';

class _Member {
  _Member(this.id, this.sig);
  final String id;
  final SimpleKeyPair sig;
  MlsGroup? group;
}

Future<_Member> _member(String id, {int salt = 0}) async {
  final sig = await MlsCrypto.sigPairFromSeed(
      List<int>.generate(32, (i) => (salt + id.hashCode * 7 + i * 13) & 0xff));
  return _Member(id, sig);
}

Future<SimpleKeyPair> _kem(int salt) => MlsCrypto.kemPairFromSeed(
    List<int>.generate(32, (j) => (salt * 31 + j * 5 + 1) & 0xff));

/// إنشاء مجموعة بمنشئ واحد ثم إضافة البقية — وكل كومت إضافة **يطبقه كل
/// الأعضاء المنضمون سابقاً** كما يلزم البروتوكول (معالجة الكومتات بالترتيب).
Future<(MlsGroup, List<_Member>)> _setup(
    {required int capacity, required int memberCount, String id = 'g'}) async {
  final creator = await _member('owner', salt: 11);
  final g = await MlsGroup.create(
      groupId: id, sigPair: creator.sig, myMemberId: creator.id, capacity: capacity);
  creator.group = g;
  final rest = <_Member>[];
  for (var i = 1; i < memberCount; i++) {
    final m = await _member('m$i', salt: 22 + i);
    rest.add(m);
    final kem = await _kem(i);
    final slot = g.addProposal(MlsKeyPackage(
      memberId: m.id,
      kemPub: (await kem.extractPublicKey()).bytes,
      sigPub: (await m.sig.extractPublicKey()).bytes,
    ))!;
    final (commit, welcomes) = (await g.commit())!;
    final bytes = commit.serialize();
    // كل من سبقه يطبق الكومت (العضو الحالي ينضم بالترحيب بعد قليل)
    for (var j = 0; j < rest.length - 1; j++) {
      final ok = await rest[j].group!.applyCommit(bytes);
      expect(ok, isTrue, reason: 'العضو المنضم سابقاً يطبق كومت الإضافة');
    }
    m.group = await MlsGroup.joinFromWelcome(
      welcomeBytes: welcomes.firstWhere((w) => w.myLeaf == slot).serialize(),
      sigPair: m.sig,
      myLeafKem: kem,
      myMemberId: m.id,
    );
    expect(m.group, isNotNull, reason: 'العضو ${m.id} انضم');
    expect(m.group!.epoch, g.epoch, reason: 'المنضم الجديد على عهد الكومت نفسه');
  }
  return (g, rest);
}

void main() {
  group('التقارب والتشفير', () {
    test('إنشاء وثلاث إضافات: الجميع على نفس العهد وسر العهد متساوٍ', () async {
      final (g, others) = await _setup(capacity: 8, memberCount: 4);
      expect(g.epoch, 3); // إنشاء + 3 كومتات إضافة
      for (final m in others) {
        expect(m.group!.epoch, g.epoch);
        expect(m.group!.epochSecret, g.epochSecret);
      }
    });

    test('حماية/فك بين كل الأعضاء (كل-إلى-كل) في مجموعة خمسة', () async {
      final (g, others) = await _setup(capacity: 8, memberCount: 5);
      final all = [g, ...others.map((m) => m.group!)];
      for (final sender in all) {
        final plain = utf8.encode('سلام من ورقة ${sender.myLeaf}');
        final frame = await sender.protect(plain);
        for (final receiver in all) {
          final pt = await receiver.unprotect(frame);
          expect(pt, isNotNull, reason: 'الجميع يفك الجميع');
          expect(utf8.decode(pt!), utf8.decode(plain));
        }
      }
    });

    test('سلسلة الأجيال: الجيل الأحدث يفك والعودة إليه إعادة عرض مرفوضة', () async {
      final (g, others) = await _setup(capacity: 4, memberCount: 2);
      final peer = others.first.group!;
      final plain0 = utf8.encode('أولى');
      final f0 = await g.protect(plain0);
      final plain1 = utf8.encode('ثانية');
      final f1 = await g.protect(plain1);
      expect(utf8.decode((await peer.unprotect(f1))!), utf8.decode(plain1));
      expect(await peer.unprotect(f0), isNull,
          reason: 'الجيل الأقدم بعد الأحدث — حماية إعادة العرض داخل العهد');
    });

    test('إطار مجموعة أخرى يفشل (ربط AAD بالمجموعة)', () async {
      final (g1, _) = await _setup(capacity: 4, memberCount: 2, id: 'a');
      final (g2, _) = await _setup(capacity: 4, memberCount: 2, id: 'b');
      final frame = await g1.protect(utf8.encode('خ'));
      expect(await g2.unprotect(frame), isNull);
    });
  });

  group('إثبات log₂(N) — الجمعات الضخمة (المرحلة: أكثر من 256 عضواً)', () {
    test('شجرة سعة 512: طول المسار المباشر = 10 (log₂+1) وكومت تحديث بأظرفة معدودة يصل لكل عضو',
        () async {
      // رياضيات الشجرة على السعة المستهدفة بالخارطة (أكثر من 256 عضواً)
      expect(nodeCount(512), 1023);
      expect(directPath(0, 512).length, 10, reason: 'log₂(512)+1');
      expect(directPath(257, 512).length, 10);
      expect(directPath(511, 512).length, 10);

      final creator = await _member('owner', salt: 31);
      final g = await MlsGroup.create(
          groupId: 'mega', sigPair: creator.sig, myMemberId: 'owner', capacity: 512);
      final joined = <MlsGroup>[]; // المجموعات المنضمة (بترتيب الانضمام)
      for (var i = 1; i <= 2; i++) {
        final m = await _member('m$i', salt: 40 + i);
        final kem = await _kem(100 + i);
        final slot = g.addProposal(MlsKeyPackage(
          memberId: m.id,
          kemPub: (await kem.extractPublicKey()).bytes,
          sigPub: (await m.sig.extractPublicKey()).bytes,
        ))!;
        final (commit, welcomes) = (await g.commit())!;
        // كل من سبقه يطبق كومت الإضافة (الترتيب إلزامي)
        for (final grp in joined) {
          expect(await grp.applyCommit(commit.serialize()), isTrue);
        }
        final grp = await MlsGroup.joinFromWelcome(
          welcomeBytes:
              welcomes.firstWhere((w) => w.myLeaf == slot).serialize(),
          sigPair: m.sig,
          myLeafKem: kem,
          myMemberId: m.id,
        );
        expect(grp, isNotNull);
        expect(grp!.epochSecret, g.epochSecret);
        joined.add(grp);
      }
      // تحديث المنشئ: شجرة منتظمة قليلة الأعضاء — أظرفة بمستوى المسار
      final (commit, _) = (await g.commit())!;
      expect(commit.envelopes.length, lessThanOrEqualTo(9 + 4),
          reason: 'log₂(512)=9 + هامش unmerged — لا أظرفة بقدر الأعضاء');
      for (final grp in joined) {
        expect(await grp.applyCommit(commit.serialize()), isTrue,
            reason: 'كل عضو يفك الكومت');
        expect(grp.epochSecret, g.epochSecret);
      }
      final frame = await g.protect(utf8.encode('ضخم'));
      expect(utf8.decode((await joined.last.unprotect(frame))!), 'ضخم');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('حالة الاستقرار المفتاحية: تحديثات متتالية من كل الأعضاء والجميع يتقارب كل مرة',
        () async {
      final (g, others) = await _setup(capacity: 8, memberCount: 5);
      final groups = <MlsGroup>[g, ...others.map((m) => m.group!)];
      for (var round = 0; round < groups.length; round++) {
        final committer = groups[round];
        final (commit, _) = (await committer.commit())!;
        for (final grp in groups) {
          if (grp == committer) continue;
          expect(await grp.applyCommit(commit.serialize()), isTrue,
              reason: 'العضو ${grp.myLeaf} يفك كومت الورقة ${committer.myLeaf}');
          expect(grp.epoch, committer.epoch);
          expect(grp.epochSecret, committer.epochSecret);
        }
      }
      // بعد تكييف الجميع (شجرة مفتاحية): أظرفة الكومت التالي بمستوى المسار
      final (commit, _) = (await g.commit())!;
      expect(commit.envelopes.length, lessThanOrEqualTo(5),
          reason: 'log₂(8)=3 + هامش — التكلفة لوغاريتمية لا خطية');
    });
  });

  group('السرية الأمامية والإقصاء', () {
    test('المنضم الجديد لا يفك رسائل ما قبل عهده (سرية أمامية مقصودة)', () async {
      final (g, others) = await _setup(capacity: 4, memberCount: 2);
      final oldFrame = await g.protect(utf8.encode('سر قديم'));
      final newcomer = await _member('m3', salt: 55);
      final kem = await _kem(77);
      final slot = g.addProposal(MlsKeyPackage(
        memberId: newcomer.id,
        kemPub: (await kem.extractPublicKey()).bytes,
        sigPub: (await newcomer.sig.extractPublicKey()).bytes,
      ))!;
      final (commit, welcomes) = (await g.commit())!;
      // العضو الأول المنضم يطبق كومت الإضافة أيضاً (الترتيب إلزامي)
      expect(await others.first.group!.applyCommit(commit.serialize()), isTrue);
      newcomer.group = await MlsGroup.joinFromWelcome(
        welcomeBytes: welcomes.firstWhere((w) => w.myLeaf == slot).serialize(),
        sigPair: newcomer.sig,
        myLeafKem: kem,
        myMemberId: newcomer.id,
      );
      expect(await newcomer.group!.unprotect(oldFrame), isNull,
          reason: 'السرية الأمامية تعني ذلك عمداً — التصميم §7');
      final newFrame = await g.protect(utf8.encode('جديد'));
      expect(utf8.decode((await newcomer.group!.unprotect(newFrame))!), 'جديد');
    });

    test('المزال لا يفك رسائل العهد بعد إزالته (إقصاء فعلي)', () async {
      final (g, others) = await _setup(capacity: 4, memberCount: 3);
      final victim = others.first; // m1 في الورقة 1
      final victimGroup = victim.group!;
      g.removeProposal(1);
      final (commit, _) = (await g.commit())!;
      final survivor = others.last.group!;
      expect(await survivor.applyCommit(commit.serialize()), isTrue);
      expect(survivor.epoch, g.epoch);
      final frame = await g.protect(utf8.encode('بعد الإزالة'));
      expect(await victimGroup.unprotect(frame), isNull,
          reason: 'سر الجذر الجديد من مسار المنشئ — لا مشتاق عكسي للمزال');
      expect(utf8.decode((await survivor.unprotect(frame))!), 'بعد الإزالة');
    });

    test('كومت مُعبث به يُرفض (توقيع بهوية الكاتب المسجلة)', () async {
      final (g, others) = await _setup(capacity: 4, memberCount: 2);
      final peer = others.first.group!;
      final (commit, _) = (await g.commit())!;
      final bytes = commit.serialize();
      final tampered = Uint8List.fromList(bytes);
      tampered[tampered.length - 80] ^= 0x01;
      expect(await peer.applyCommit(tampered), isFalse,
          reason: 'التوقيع بهوية الكاتب المسجلة يكشف أي تعديل');
      expect(await peer.applyCommit(bytes), isTrue);
    });

    test('الكومت المتأخر على عهد منقضٍ يُرفض (ترتيب الكومتات إلزامي)', () async {
      final (g, others) = await _setup(capacity: 4, memberCount: 2);
      final peer = others.first.group!;
      final (stale, _) = (await g.commit())!;
      expect(await peer.applyCommit(stale.serialize()), isTrue);
      final (fresh, _) = (await g.commit())!;
      expect(await peer.applyCommit(fresh.serialize()), isTrue);
      // إعادة تطبيق الكومت الأول على العهد المتقدم — رفض
      expect(await peer.applyCommit(stale.serialize()), isFalse,
          reason: 'الكومت لعهد انقضى — لا قبول متأخر');
    });
  });

  group('بوابة التوافق مع التشفير الحالي', () {
    test('فصل العلامات: اشتقاقات wasl-mls لا تتعادل مع wasl-dr لسلسلة الجلسات',
        () async {
      final ikm = List<int>.generate(32, (i) => i);
      final salt = List<int>.generate(32, (i) => 255 - i);
      final mls = await _hk(ikm, salt, MlsCrypto.infoSender);
      final dr = await _hk(ikm, salt, 'wasl-dr-msg-v1');
      final drRoot = await _hk(ikm, salt, 'wasl-dr-rk-v1');
      expect(_eq(mls, dr), isFalse,
          reason: 'مفاتيح المجموعة الكبيرة مستقلة عن مفاتيح الجلسة الثنائية');
      expect(_eq(mls, drRoot), isFalse);
    });

    test('الطيف المشترك: AES-GCM نفسه يفك ما شفرته بنفس المفتاح — توافق الأوليات',
        () async {
      final key = List<int>.generate(32, (i) => i * 3 + 1);
      final nonce = List<int>.generate(12, (i) => i);
      final ct = await MlsCrypto.aesEncrypt(key, nonce, utf8.encode('توافق'), [1, 2]);
      final pt = await MlsCrypto.aesDecrypt(key, nonce, ct, [1, 2]);
      expect(utf8.decode(pt!), 'توافق');
      expect(await MlsCrypto.aesDecrypt(key, nonce, ct, [1, 3]), isNull,
          reason: 'AAD يوثق بالمحتوى');
    });
  });

  test('protect يرفض حمولة غير بايتية صراحة — لا قصص صامتة', () async {
      final (g, _) = await _setup(capacity: 4, memberCount: 2);
      expect(() => g.protect('ثانية'.codeUnits), throwsArgumentError,
          reason: 'وحدات UTF-16 ليست بايتات — utf8.encode هو المسار');
    });

    group('رياضيات الشجرة', () {
    test('تخطيط الكومة: أوراق n-1..2n-2 والأب (x-1)/2 والمسار المباشر', () {
      expect(nodeCount(4), 7);
      expect(leafNodeIndex(0, 4), 3);
      expect(leafNodeIndex(3, 4), 6);
      expect(leafIndexOfNode(5, 4), 2);
      expect(parentNode(0), isNull);
      expect(parentNode(3), 1);
      expect(parentNode(6), 2);
      expect(childNodes(1), [3, 4]);
      expect(directPath(0, 4), [3, 1, 0]);
      expect(directPath(2, 4), [5, 2, 0]);
    });
  });
}

Future<List<int>> _hk(List<int> ikm, List<int> salt, String info) =>
    MlsCrypto.hkdf(ikm, salt, info, 32);

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
