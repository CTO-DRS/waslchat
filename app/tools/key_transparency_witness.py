#!/usr/bin/env python3
"""شاهد شفافية المفاتيح — أداة مراقبة مفتوحة المصدر (وصل شات 1.6.0، المرحلة 15 ب).

تقرأ لقطة دورية من الدالتين الخادمتين العموميتين (ترحيل 038):
  key_log_witness_heads()  → البصمات العمياء لرؤوس سلاسل كل الحسابات
  key_log_witness_digest() → بصمة اللقطة الكلية

وتلحق سطراً واحداً JSONL بسجل الشاهد — سجل إلحاحي زمني رتيب لا يعود للخلف:
  {"ts": "...Z", "digest": "…64hex", "count": N, "heads": [{"d": "...", "len": n, "at": "..."}]}

أي إعادة كتابة لتاريخ المفاتيح على الخادم تغيّر اللقطات الجديدة عن المنشورة
قديماً فيكشف الانتهاك — لا ثقة بوعد، بل سجل قابل للتحقق.

ما تراه الأداة وما لا تراه (موثق في docs/WITNESS.md):
  + بصمات عمياء sha256('wt1|'+uid+'|'+رأس السلسلة) — لا معرّفات ولا مفاتيح
  + طول كل سلسلة ووقت آخر حدث فيها (أرقام إجمالية)
  − لا نصوص ولا بصمات مفاتيح خام ولا أجهزة ولا هويات — وصاحب الحساب وحده
    يستطيع ربط بصمته العمياء بنفسه لأنه يعرف uid ورأس سلسلته أصلاً.

الاستعمال:
  # إلحاح لقطة جديدة بسجل الشاهد (cron/Actions كل ساعة مثلاً):
  python3 key_transparency_witness.py append \
      --url https://YOUR.supabase.co --key ANON_KEY --log witness.jsonl

  # تحقق صاحب الحساب: بصمتك العمياء موجودة في كل لقطة بعد لحظتك؟
  python3 key_transparency_witness.py verify \
      --log witness.jsonl --user-id <uid> --head <رأس_السلسلة> \
      [--after 2026-11-18T00:00:00Z]

  # حساب بصمتك العمياء يدوياً (بدون خادم):
  python3 key_transparency_witness.py blind --user-id <uid> --head <رأس_السلسلة>

لا أسرار هنا إطلاقاً: مفتاح anon مفتوح بالتصميم (نفسه في التطبيق)، ودوال RPC
قراءة حصراً بلا أي مسار كتابة. مكتبة قياسية فقط (urllib/json/hashlib).
"""
import argparse
import datetime as dt
import hashlib
import json
import sys
import urllib.request

DOMAIN = "wt1"


def blind_digest(user_id: str, head: str) -> str:
    """البصمة العمياء — مطابقة للدالة الخادمية والخدمة النقية بايتاً بايتاً."""
    if not user_id or not head:
        return ""
    return hashlib.sha256(f"{DOMAIN}|{user_id}|{head}".encode()).hexdigest()


def snapshot_digest(blinds) -> str:
    """بصمة اللقطة الكلية — تجزئة البصمات مرتبة بسطر جديد."""
    sorted_blinds = sorted(b for b in blinds if b)
    return hashlib.sha256("\n".join(sorted_blinds).encode()).hexdigest()


def rpc(url: str, key: str, fn: str):
    """استدعاء RPC قراءة عبر REST بمفتاح anon المفتوح بالتصميم."""
    req = urllib.request.Request(
        f"{url.rstrip('/')}/rest/v1/rpc/{fn}",
        data=b"",
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def parse_heads(rows):
    """تحليل دفاعي لصفوف الدالة الخادمية — الناقص الجوهري يُسقط بلا ثقة."""
    heads = []
    for r in rows or []:
        d = r.get("blind_digest") or ""
        ln = r.get("chain_len")
        if not isinstance(d, str) or len(d) != 64 or not isinstance(ln, int) or ln < 1:
            continue
        heads.append({"d": d.lower(), "len": ln, "at": r.get("last_event_at") or ""})
    return heads


def cmd_append(args):
    heads = parse_heads(rpc(args.url, args.key, "key_log_witness_heads"))
    server_digest = rpc(args.url, args.key, "key_log_witness_digest")
    if not isinstance(server_digest, str) or len(server_digest) != 64:
        print("خطأ: بصمة الخادم ليست sha256 hex سليم — لا إلحاح بلا تحقق", file=sys.stderr)
        return 2
    local_digest = snapshot_digest([h["d"] for h in heads])
    if local_digest != server_digest.lower():
        print(
            f"خطأ: بصمة الخادم {server_digest} لا تطابق إعادة الحساب المحلي {local_digest} "
            "— عدم اتساق في اللقطة نفسها، لا إلحاح صامت",
            file=sys.stderr,
        )
        return 2
    if args.min_heads is not None and len(heads) < args.min_heads:
        print(
            f"خطأ: اللقطة فيها {len(heads)} بصمة وأقل حد {args.min_heads} — "
            "هبوط مفاجئ بعدد السلاسل يُرفض بلا علم (قد يكون حذف تاريخي كامل)",
            file=sys.stderr,
        )
        return 2
    if args.max_heads is not None and len(heads) > args.max_heads:
        print(
            f"خطأ: اللقطة فيها {len(heads)} بصمة وأعلى حد {args.max_heads} — "
            "نمو مفاجئ فوق المتوقع يُرفض للمراجعة البشرية",
            file=sys.stderr,
        )
        return 2
    line = json.dumps(
        {
            "ts": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "digest": local_digest,
            "count": len(heads),
            "heads": heads,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
    with open(args.log, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(f"أُلحِحت لقطة: {local_digest} بعدد سلاسل {len(heads)} في {args.log}")
    return 0


def load_log(path):
    snaps = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
                ts = o.get("ts")
                digest = o.get("digest")
                if (
                    not isinstance(ts, str)
                    or not isinstance(digest, str)
                    or len(digest) != 64
                ):
                    continue
                dt.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
                heads = []
                for h in o.get("heads") or []:
                    d = h.get("d") or ""
                    ln = h.get("len")
                    if isinstance(d, str) and len(d) == 64 and isinstance(ln, int) and ln >= 1:
                        heads.append(d.lower())
                snaps.append({"ts": ts, "digest": digest.lower(), "heads": heads})
            except (json.JSONDecodeError, ValueError):
                continue
    # رتابة زمنية صارمة — سجل إلحاحي لا يعود للخلف
    last = None
    clean = []
    for s in snaps:
        cur = dt.datetime.strptime(s["ts"], "%Y-%m-%dT%H:%M:%SZ")
        if last is not None and cur < last:
            print(f"تنبيه: السجل يعود للخلف عند {s['ts']} — سجل ليس إلحاحياً سليماً", file=sys.stderr)
            return None
        last = cur
        clean.append(s)
    return clean


def cmd_verify(args):
    snaps = load_log(args.log)
    if snaps is None:
        return 2
    blind = blind_digest(args.user_id, args.head)
    if not blind:
        print("خطأ: معرّف أو رأس سلسلة فارغ — لا تحقق بلا مدخلات سليمة", file=sys.stderr)
        return 2
    after = (
        dt.datetime.strptime(args.after, "%Y-%m-%dT%H:%M:%SZ")
        if args.after
        else dt.datetime(1970, 1, 1)
    )
    checked = missing = 0
    first_missing = None
    for s in snaps:
        ts = dt.datetime.strptime(s["ts"], "%Y-%m-%dT%H:%M:%SZ")
        if ts <= after:
            continue
        checked += 1
        if blind not in s["heads"]:
            missing += 1
            first_missing = first_missing or s["ts"]
    print(f"بصمتك العمياء: {blind}")
    print(f"اللقطات المفحوصة بعد {after.isoformat()}: {checked}")
    if missing == 0:
        print("النتيجة: بصمتك حاضرة في كل لقطة — الشاهد يوثق سلامة سلسلتك في هذه الفترة")
        return 0
    print(f"النتيجة: {missing} لقطة بلا بصمتك — أول لحظة ناقصة {first_missing}")
    print("هذا إعلان انتهاك محتمل: إما سلسلتك أُعيدت كتابتها، أو الشاهد انقطع — راجع سجل مفاتيحي في التطبيق ثم الشهود الآخرين")
    return 1


def cmd_blind(args):
    print(blind_digest(args.user_id, args.head))
    return 0


def main():
    ap = argparse.ArgumentParser(description="شاهد شفافية المفاتيح — وصل شات")
    sub = ap.add_subparsers(dest="cmd", required=True)

    ap_a = sub.add_parser("append", help="إلحاح لقطة جديدة بسجل الشاهد")
    ap_a.add_argument("--url", required=True, help="Supabase URL العام")
    ap_a.add_argument("--key", required=True, help="مفتاح anon (مفتوح بالتصميم)")
    ap_a.add_argument("--log", required=True, help="مسار ملف سجل الشاهد JSONL")
    ap_a.add_argument("--min-heads", type=int, default=None, help="أقل عدد سلاسل مقبول (إلغاء الهبوط الصامت)")
    ap_a.add_argument("--max-heads", type=int, default=None, help="أعلى عدد سلاسل مقبول (إلغاء النمو الصامت)")

    ap_v = sub.add_parser("verify", help="تحقق صاحب الحساب من سجل الشاهد")
    ap_v.add_argument("--log", required=True)
    ap_v.add_argument("--user-id", required=True)
    ap_v.add_argument("--head", required=True, help="رأس سلسلتك من «سجل مفاتيحي»")
    ap_v.add_argument("--after", default=None, help="فحص اللقطات بعد هذه اللحظة فقط")

    ap_b = sub.add_parser("blind", help="حساب بصمتك العمياء يدوياً")
    ap_b.add_argument("--user-id", required=True)
    ap_b.add_argument("--head", required=True)

    args = ap.parse_args()
    return {"append": cmd_append, "verify": cmd_verify, "blind": cmd_blind}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
