import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/room_permissions_service.dart';

/// اختبارات صلاحيات الغرفة (0.5.0 — المرحلة 3 بند 1).
/// المنطق هنا يجب أن يطابق حرفياً الفرض الخادمي في
/// supabase/028_room_permissions.sql — واختبار «المطابقة مع ملف
/// الترحيل» يمنع انحراف أحدهما عن الآخر مستقبلاً.
void main() {
  final migration =
      File('supabase/028_room_permissions.sql').readAsStringSync();

  // ---------- الثوابت والافتراضات ----------

  test('الافتراضات الست مطابقة للسلوك القديم حرفياً', () {
    expect(kRoomPermDefaults.length, 6);
    // الوسائط والصوت والاستطلاعات كانت مسموحة دائماً
    expect(kRoomPermDefaults['member_media'], isTrue);
    expect(kRoomPermDefaults['member_voice'], isTrue);
    expect(kRoomPermDefaults['member_polls'], isTrue);
    // الدعوات كانت للمالك والمشرفين فقط
    expect(kRoomPermDefaults['member_invites'], isFalse);
    // إدارة الأعضاء وتغيير الاسم كانت للمشرفين
    expect(kRoomPermDefaults['admin_manage_members'], isTrue);
    expect(kRoomPermDefaults['admin_edit_info'], isTrue);
  });

  test('كل مفتاح في enum موجود في ملف الترحيل ومطابق لقائمة المسموح بها',
      () {
    for (final p in RoomPermKey.values) {
      expect(migration.contains("'^${p.key}'") || migration.contains("'${p.key}'"),
          isTrue,
          reason: 'المفتاح ${p.key} يجب أن يكون في 028_room_permissions.sql');
    }
    // دالة room_permission تعيد true افتراضياً لخمس صلاحيات، وليس member_invites
    final defaultTrue = RegExp(r"p_perm in \(([^)]+)\)", multiLine: true)
        .firstMatch(migration)!
        .group(1)!;
    for (final p in RoomPermKey.values) {
      final inSql = defaultTrue.contains(p.key);
      expect(inSql, p.key != 'member_invites',
          reason: 'الافتراضي في SQL لـ${p.key} يجب أن يطابق Dart');
    }
  });

  test('الفرض الخادمي موجود في ملف الترحيل: can_send في سياسة الإدراج', () {
    expect(migration.contains('can_send(conversation_id, type)'), isTrue);
    expect(migration.contains('owner only'), isTrue);
  });

  // ---------- التحليل ----------

  test('تحليل استجابة my_room_perms: الدور والخريطة', () {
    final raw = jsonDecode('''
      {"role": "admin", "perms": {"member_media": true, "member_voice": false}}
    ''') as Map<String, dynamic>;
    final p = RoomPerms.parse(raw);
    expect(p.role, 'admin');
    expect(p.perms['member_media'], isTrue);
    expect(p.perms['member_voice'], isFalse);
  });

  test('القيم غير البوليانية تُهمل ولا تُقبل تحويلات لينة', () {
    final raw = jsonDecode('''
      {"role": "member",
       "perms": {"member_media": "true", "member_polls": 1, "member_voice": true}}
    ''') as Map<String, dynamic>;
    final p = RoomPerms.parse(raw);
    // member_media وmember_polls أُهملتا فسقطتا للاسم الافتراضي
    expect(p.allows(RoomPermKey.media), isTrue);
    expect(p.allows(RoomPermKey.polls), isTrue);
    expect(p.allows(RoomPermKey.voice), isTrue);
  });

  test('الدور المجهول أو غيره يعاد none عند غيابه', () {
    expect(RoomPerms.parse({}).role, 'none');
    expect(RoomPerms.parse({'role': 5}).role, 'none');
  });

  // ---------- منطق allows لكل دور ----------

  test('المالك فوق كل شيء حتى مع خريطة قيود كاملة', () {
    final p = RoomPerms(
        role: 'owner',
        perms: {
          for (final k in kRoomPermDefaults.keys) k: false,
        });
    for (final k in RoomPermKey.values) {
      expect(p.allows(k), isTrue, reason: 'المالك يملك ${k.key} دائماً');
    }
  });

  test('المشرف فوق قيود الأعضاء، وصلاحياته الإدارية بحسب الغرفة', () {
    // غرفة قيّد المالك فيها كل شيء
    final restricted = RoomPerms(
        role: 'admin',
        perms: {
          'member_media': false,
          'member_voice': false,
          'member_polls': false,
          'member_invites': false,
          'admin_manage_members': false,
          'admin_edit_info': false,
        });
    // صلاحيات الأعضاء مضمّنة للمشرف (كالخادم في can_send)
    expect(restricted.canSendMedia, isTrue);
    expect(restricted.canSendVoice, isTrue);
    expect(restricted.canSendPolls, isTrue);
    expect(restricted.canInvite, isTrue);
    // القدرات الإدارية مقيدة فعلًا
    expect(restricted.canManageMembers, isFalse);
    expect(restricted.canEditInfo, isFalse);

    // غرفة بلا قيود (خريطة فارغة = افتراضيات)
    final normal = const RoomPerms(role: 'admin', perms: {});
    expect(normal.canManageMembers, isTrue);
    expect(normal.canEditInfo, isTrue);
    expect(normal.canInvite, isTrue);
  });

  test('العضو يخضع للقيود ولا يملك صلاحيات إدارية أبداً', () {
    final p = RoomPerms(role: 'member', perms: {'member_media': false});
    expect(p.canSendMedia, isFalse);
    expect(p.canSendVoice, isTrue); // الافتراضي
    expect(p.canSendPolls, isTrue);
    expect(p.canInvite, isFalse); // الافتراضي كما كان
    expect(p.canManageMembers, isFalse);
    expect(p.canEditInfo, isFalse);

    // فتح الدعوات للأعضاء يظهر فوراً
    final opened = RoomPerms(role: 'member', perms: {'member_invites': true});
    expect(opened.canInvite, isTrue);
    expect(opened.canManageMembers, isFalse);
  });

  test('غير العضو لا شيء، وغير الأعضاء لا يعرف الدعوة', () {
    final p = const RoomPerms(role: 'none', perms: {});
    for (final k in RoomPermKey.values) {
      expect(p.allows(k), isFalse);
    }
  });

  test('المفتاح المجهول في الخريطة يُهمل ولا يفسد البقية', () {
    final p = RoomPerms(role: 'member', perms: {
      'rogue_key': true,
      'member_media': false,
    });
    expect(p.canSendMedia, isFalse);
    expect(p.canSendVoice, isTrue);
  });

  // ---------- رسائل الرفض ----------

  test('رسائل الرفض عربية وواضحة لكل شكل رفض خادمي', () {
    expect(
        RoomPermissionsService.rejectionMessage(
            Exception('PostgREST: owner only')),
        contains('مالك المجموعة'));
    expect(
        RoomPermissionsService.rejectionMessage(Exception('forbidden')),
        contains('قيّد'));
    expect(
        RoomPermissionsService.rejectionMessage(
            Exception('new row violates row-level security policy')),
        contains('قيّد'));
    expect(
        RoomPermissionsService.rejectionMessage(Exception('connection lost')),
        'تعذّر تنفيذ الطلب');
  });
}
