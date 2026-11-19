#!/usr/bin/env python3
"""Wasl Shield — اختبارات أمنية حقيقية ضد قاعدة Supabase عبر واجهاتها العامة (PostgREST/Storage/Edge).

ينشئ حسابات اختبار مؤقتة (shieldtest_*) ثم يحذفها. يحتاج:
  - sbq: أمر يقرأ SQL من stdin وينفذه بصلاحية الإدارة (Management API).
  - ANON key من lib/config.dart.
  - SERVICE key لتنظيف ملفات التخزين فقط (يُقرأ من البيئة WASL_SERVICE_KEY، لا يُطبع).
"""
import json, os, subprocess, sys, time, uuid, hashlib, urllib.request, urllib.error, re

REF = "hplzbillnbdjtufazrlp"
BASE = f"https://{REF}.supabase.co"
ANON = re.search(r"supabaseAnonKey = '([^']+)'", open("lib/config.dart").read()).group(1)
SERVICE = os.environ.get("WASL_SERVICE_KEY", "")
SBQ = os.environ.get("SBQ", "python3 /workspace/tools/sbq.py")
PW = "T3st-" + uuid.uuid4().hex
results = []


def sql(q):
    r = subprocess.run(SBQ, shell=True, input=q, capture_output=True, text=True).stdout
    if re.match(r"^\d{3} ", r):
        raise RuntimeError(r[:400])
    return json.loads(r) if r.strip() else []


def http(method, path, token=None, body=None, headers=None, raw=False):
    h = {"apikey": ANON, "Authorization": f"Bearer {token or ANON}"}
    if headers: h.update(headers)
    data = None
    if body is not None:
        if isinstance(body, (bytes, bytearray)):
            data = body
        else:
            data = json.dumps(body).encode(); h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            b = r.read(); return r.status, (b if raw else (json.loads(b) if b else None))
    except urllib.error.HTTPError as e:
        b = e.read()
        try: return e.code, json.loads(b)
        except Exception: return e.code, b.decode(errors="ignore")


def rpc(token, fn, params=None):
    return http("POST", f"/rest/v1/rpc/{fn}", token, params or {})


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))
    print(("PASS " if cond else "FAIL ") + name + (f"  [{detail}]" if detail and not cond else ""))


def mk_user(tag):
    uid = str(uuid.uuid4()); email = f"shieldtest_{tag}_{uid[:6]}@example.com"
    sql(f"""insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
          raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
          confirmation_token,recovery_token,email_change_token_new,email_change)
        values ('00000000-0000-0000-0000-000000000000','{uid}','authenticated','authenticated','{email}',
          crypt('{PW}', gen_salt('bf')), now(), '{{"provider":"email","providers":["email"]}}',
          '{{"username":"shieldtest_{tag}"}}', now(), now(), '', '', '', '');""")
    st, tok = http("POST", "/auth/v1/token?grant_type=password", None, {"email": email, "password": PW})
    assert st == 200, (st, tok)
    return uid, tok["access_token"], email


def main():
    users = {}
    try:
        for t in ["reporter", "target", "outsider", "admin"]:
            users[t] = mk_user(t)
        A, Atok, _ = users["reporter"]; B, Btok, Bemail = users["target"]; C, Ctok, _ = users["outsider"]
        D, Dtok, _ = users["admin"]
        sql(f"insert into app_admins (user_id) values ('{D}');")

        # محادثة مباشرة A-B عبر الواجهة الحقيقية
        st, conv = rpc(Atok, "create_direct_chat", {"other_id": B})
        if st != 200:
            st, conv = rpc(Atok, "create_direct_chat", {"p_other": B})
        check("setup: create_direct_chat", st == 200, f"{st} {conv}")
        conv = conv if isinstance(conv, str) else (conv[0] if isinstance(conv, list) else conv)

        # B يرفع صورة ويرسلها
        path = f"{conv}/{int(time.time()*1000)}_{B[:8]}.jpg"
        st, _ = http("POST", f"/storage/v1/object/chat-media/{path}", Btok, b"\xff\xd8\xff fake-jpeg",
                     {"Content-Type": "image/jpeg"})
        check("setup: target uploads media", st == 200, st)
        st, m = http("POST", "/rest/v1/messages", Btok,
                     {"conversation_id": conv, "sender_id": B, "type": "image", "media_url": path, "content": ""},
                     {"Prefer": "return=representation"})
        check("setup: target sends media message", st == 201, f"{st} {m}")
        mid = m[0]["id"] if st == 201 else None
        st, signed = http("POST", f"/storage/v1/object/sign/chat-media/{path}", Atok, {"expiresIn": 3600})
        check("setup: reporter gets signed url", st == 200, st)
        signed_url = BASE + "/storage/v1" + signed["signedURL"] if st == 200 else None
        st, _ = http("GET", signed_url.replace(BASE, ""), raw=True) if signed_url else (0, None)
        check("setup: signed url works before revoke", st == 200, st)

        # 1) تزوير بلاغ: طرف لا علاقة له
        st, r = rpc(Ctok, "shield_report", {"p_category": "blackmail", "p_description": "fake report",
                                           "p_urgent": True, "p_target": B})
        check("abuse: outsider cannot report unrelated user", st >= 400 and "SHIELD_NO_RELATION" in json.dumps(r), r)
        st, r = rpc(Ctok, "shield_report", {"p_category": "blackmail", "p_description": "fake",
                                           "p_urgent": True, "p_conversation": conv})
        check("abuse: outsider cannot report on a conversation he is not in", st >= 400, r)
        st, r = rpc(Atok, "shield_report", {"p_category": "hack", "p_description": "xxxx", "p_urgent": False})
        check("abuse: invalid category rejected", st >= 400, r)

        # 2) بلاغ حقيقي
        st, r = rpc(Atok, "shield_report", {"p_category": "blackmail", "p_description": "يهددني بنشر صوري",
                                           "p_urgent": True, "p_target": B, "p_conversation": conv,
                                           "p_block": True})
        check("report: reporter files urgent blackmail report", st == 200 and r, r)
        case = r[0]["case_id"]; ref = r[0]["ref"]
        sev = sql(f"select severity from shield_cases where id='{case}'")[0]["severity"]
        check("report: severity computed server-side = critical", sev == "critical", sev)
        blk = sql(f"select count(*) n from blocks where blocker='{A}' and blocked='{B}'")[0]["n"]
        check("report: silent block applied", blk == 1)

        # 3) سرية المبلِّغ
        st, rows = http("GET", "/rest/v1/shield_cases?select=*", Btok)
        check("privacy: target sees no cases", st == 200 and rows == [], rows)
        st, rows = http("GET", "/rest/v1/shield_cases?select=*", Ctok)
        check("privacy: outsider sees no cases", st == 200 and rows == [], rows)
        st, rows = http("GET", "/rest/v1/shield_cases?select=id", Atok)
        check("privacy: reporter sees own case", st == 200 and len(rows) == 1, rows)
        for t in ["shield_evidence", "shield_audit", "shield_quarantine", "shield_restrictions"]:
            st, rows = http("GET", f"/rest/v1/{t}?select=*", Atok)
            check(f"privacy: {t} not readable by users", st != 200 or rows == [], f"{st} {rows}")
        st, msgs = http("GET", f"/rest/v1/messages?select=content&conversation_id=eq.{conv}", Btok)
        check("privacy: no trace of report in target's chat", st == 200 and all("بلاغ" not in (x["content"] or "") for x in msgs))

        # 4) صلاحيات الإدارة
        for fn, p in [("shield_admin_cases", {}), ("shield_admin_case", {"p_case": case}),
                      ("shield_admin_audit", {}), ("shield_admin_suspend", {"p_case": case, "p_suspend": True, "p_reason": "test reason"}),
                      ("shield_admin_message_reporter", {"p_case": case, "p_text": "hi"})]:
            st, r = rpc(Atok, fn, p)
            check(f"rbac: non-admin denied {fn}", st >= 400 and "not_admin" in json.dumps(r), f"{st} {r}")
        st, r = rpc(Atok, "_shield_log", {"p_case": case, "p_action": "x", "p_target": None, "p_reason": None})
        check("rbac: internal _shield_log not callable", st >= 400, st)
        st, r = rpc(Atok, "shield_service_purge_case", {"p_case": case})
        check("rbac: service purge not callable by users", st >= 400, st)
        st, r = rpc(Dtok, "shield_admin_cases", {})
        check("rbac: admin lists cases", st == 200 and any(x["id"] == case for x in r), st)

        # 5) الإشعار والتأكيد
        n = sql(f"""select count(*) n from messages m join conversation_participants p on p.conversation_id=m.conversation_id
                   where p.user_id='{D}' and m.content like '%{ref}%'""")[0]["n"]
        check("notify: admin received instant notification message", n >= 1)
        n = sql(f"""select count(*) n from messages m join conversation_participants p on p.conversation_id=m.conversation_id
                   where p.user_id='{A}' and m.content like '%{ref}%' and m.sender_id=public.official_id('support')""")[0]["n"]
        check("notify: reporter got confirmation from support", n >= 1)

        # 6) الأدلة
        ev = json.dumps([{"from": "target", "text": "سأنشر صورك"}], ensure_ascii=False).encode()
        epath = f"{case}/{uuid.uuid4()}.json"
        st, _ = http("POST", f"/storage/v1/object/shield-evidence/{epath}", Atok, ev, {"Content-Type": "application/json"})
        check("evidence: reporter uploads to own case", st == 200, st)
        st, _ = http("POST", f"/storage/v1/object/shield-evidence/{case}/evil.json", Ctok, b"{}", {"Content-Type": "application/json"})
        check("evidence: outsider cannot upload into case", st >= 400, st)
        st, eid = rpc(Atok, "shield_add_evidence", {"p_case": case, "p_kind": "messages", "p_path": epath,
                                                    "p_mime": "application/json", "p_size": len(ev),
                                                    "p_sha256": hashlib.sha256(ev).hexdigest()})
        check("evidence: registered", st == 200, eid)
        st, r = rpc(Ctok, "shield_add_evidence", {"p_case": case, "p_kind": "messages", "p_path": epath,
                                                  "p_mime": "x", "p_size": 1, "p_sha256": "x"})
        check("evidence: outsider cannot register evidence", st >= 400, r)
        st, _ = http("GET", f"/storage/v1/object/authenticated/shield-evidence/{epath}", Atok, raw=True)
        check("evidence: reporter cannot read back from server", st >= 400, st)
        st, _ = http("GET", f"/storage/v1/object/authenticated/shield-evidence/{epath}", Btok, raw=True)
        check("evidence: target cannot read", st >= 400, st)
        st, _ = http("GET", f"/storage/v1/object/authenticated/shield-evidence/{epath}", Dtok, raw=True)
        check("evidence: admin cannot read WITHOUT audited open", st >= 400, st)
        st, p = rpc(Dtok, "shield_admin_open_evidence", {"p_evidence": eid})
        check("evidence: admin audited open returns path", st == 200 and p == epath, p)
        st, body = http("GET", f"/storage/v1/object/authenticated/shield-evidence/{epath}", Dtok, raw=True)
        check("evidence: admin reads after audited open, intact", st == 200 and hashlib.sha256(body).hexdigest() == hashlib.sha256(ev).hexdigest(), st)
        n = sql(f"select count(*) n from shield_audit where case_id='{case}' and action='evidence_open'")[0]["n"]
        check("audit: evidence open logged", n == 1)

        # 7) إبطال الروابط (الحجر)
        st, r = http("POST", "/functions/v1/shield-admin", Atok, {"action": "quarantine", "case_id": case,
                                                                  "message_ids": [mid], "reason": "test reason"})
        check("revoke: non-admin cannot quarantine", st == 403, f"{st} {r}")
        st, r = http("POST", "/functions/v1/shield-admin", Dtok, {"action": "quarantine", "case_id": case,
                                                                  "message_ids": [mid], "reason": ""})
        check("revoke: justification required", st == 400, r)
        st, r = http("POST", "/functions/v1/shield-admin", Dtok, {"action": "quarantine", "case_id": case,
                                                                  "message_ids": [mid], "reason": "تهديد موثق بالأدلة"})
        check("revoke: admin quarantines media", st == 200 and r.get("quarantined") == 1, f"{st} {r}")
        dead_at = None
        for i in range(10):
            st, _ = http("GET", signed_url.replace(BASE, ""), raw=True)
            if st >= 400: dead_at = i * 10; break
            time.sleep(10)
        check("revoke: exact previously issued url dead within CDN window (<=90s)", dead_at is not None, f"seconds={dead_at}")
        print("   CDN invalidation observed after ~", dead_at, "s")
        st, _ = http("POST", f"/storage/v1/object/sign/chat-media/{path}", Btok, {"expiresIn": 60})
        check("revoke: target cannot mint new link", st >= 400, st)
        st, _ = http("GET", f"/storage/v1/object/authenticated/shield-quarantine/{case}/{path}", Dtok, raw=True)
        check("revoke: quarantine not readable even by admin client", st >= 400, st)
        rm = sql(f"select shield_removed from messages where id='{mid}'")[0]["shield_removed"]
        check("revoke: message flagged removed", rm is True)
        st, _ = http("PATCH", f"/rest/v1/messages?id=eq.{mid}", Btok, {"shield_removed": False, "protected": True})
        rm = sql(f"select shield_removed from messages where id='{mid}'")[0]["shield_removed"]
        check("tamper: target cannot unflag removed media", rm is True, st)

        # 8) قيود الوسائط والتعليق
        st, r = rpc(Dtok, "shield_admin_restrict_media", {"p_case": case, "p_restrict": True, "p_reason": "x"})
        check("action: reason too short rejected", st >= 400 and "REASON" in json.dumps(r), r)
        st, r = rpc(Dtok, "shield_admin_restrict_media", {"p_case": case, "p_restrict": True, "p_reason": "منع إرسال الوسائط"})
        check("action: restrict media", st in (200, 204), f"{st} {r}")
        st, r = http("POST", "/rest/v1/messages", Btok, {"conversation_id": conv, "sender_id": B, "type": "image",
                                                          "media_url": f"{conv}/x.jpg", "content": ""})
        check("action: restricted target cannot send media", st >= 400 and "SHIELD_MEDIA_RESTRICTED" in json.dumps(r), f"{st} {r}")
        st, r = rpc(Dtok, "shield_admin_message_reporter", {"p_case": case, "p_text": "نحن معك، تم اتخاذ إجراء"})
        check("comms: admin messages reporter as support", st in (200, 204), f"{st} {r}")
        st, th = rpc(Dtok, "shield_admin_thread", {"p_case": case})
        check("comms: admin sees support thread", st == 200 and any("نحن معك" in (x["content"] or "") for x in th), f"{st} {th}")
        st, r = rpc(Dtok, "shield_admin_suspend", {"p_case": case, "p_suspend": True, "p_reason": "ابتزاز مؤكد"})
        check("action: suspend target", st in (200, 204), f"{st} {r}")
        st, r = http("POST", "/auth/v1/token?grant_type=password", None, {"email": Bemail, "password": PW})
        check("action: suspended target cannot sign in", st >= 400, st)
        st, r = rpc(Dtok, "shield_admin_suspend", {"p_case": case, "p_suspend": True, "p_reason": "test protect"})
        sql(f"update shield_cases set target_user='{D}' where id='{case}'")
        st, r = rpc(Dtok, "shield_admin_suspend", {"p_case": case, "p_suspend": True, "p_reason": "suspend admin?"})
        check("action: admins/official protected from suspension", st >= 400 and "protected" in json.dumps(r), r)
        sql(f"update shield_cases set target_user='{B}' where id='{case}'")

        # 9) سجل التدقيق
        try:
            sql("update shield_audit set reason='tampered' where seq=(select max(seq) from shield_audit)")
            check("audit: update blocked", False, "update succeeded")
        except RuntimeError as e:
            check("audit: update blocked", "IMMUTABLE" in str(e), str(e)[:120])
        try:
            sql("delete from shield_audit where seq=(select max(seq) from shield_audit)")
            check("audit: delete blocked", False)
        except RuntimeError as e:
            check("audit: delete blocked", "IMMUTABLE" in str(e))
        st, v = rpc(Dtok, "shield_admin_verify_audit", {})
        check("audit: hash chain verifies", st == 200 and v.get("ok") is True, v)
        st, log = rpc(Dtok, "shield_admin_audit", {"p_case": case})
        acts = {x["action"] for x in log} if st == 200 else set()
        need = {"case_created", "evidence_added", "evidence_open", "media_quarantined", "media_restricted",
                "message_reporter", "target_suspended", "case_viewed"}
        st2, _ = rpc(Dtok, "shield_admin_case", {"p_case": case})
        st, log = rpc(Dtok, "shield_admin_audit", {"p_case": case})
        acts = {x["action"] for x in log}
        check("audit: all actions recorded", need <= acts, sorted(need - acts))

        # 10) حد البلاغات
        for i in range(4):
            rpc(Atok, "shield_report", {"p_category": "other", "p_description": f"r{i} test", "p_urgent": False})
        st, r = rpc(Atok, "shield_report", {"p_category": "other", "p_description": "sixth", "p_urgent": False})
        check("abuse: rate limit 5/day", st >= 400 and "RATE_LIMIT" in json.dumps(r), r)

        # 11) الاحتفاظ: حالة مفتوحة لا تُحذف
        st, r = http("POST", "/functions/v1/shield-admin", Atok, {"action": "retention"})
        check("retention: endpoint rejects without secret", st == 401, st)
        exp = sql(f"select count(*) n from shield_service_expired() where case_id='{case}'")[0]["n"]
        check("retention: open case evidence never expires", exp == 0)

        # 12) الإعدادات: وسائط محمية تلقائياً
        st, _ = http("POST", "/rest/v1/shield_settings", Atok, {"user_id": A, "enabled": True, "protect_media": True},
                     {"Prefer": "resolution=merge-duplicates"})
        check("settings: user saves own shield settings", st in (200, 201), st)
        st, _ = http("POST", "/rest/v1/shield_settings", Ctok, {"user_id": A, "enabled": False},
                     {"Prefer": "resolution=merge-duplicates"})
        check("settings: cannot write another user's settings", st >= 400, st)
        st, conv2 = rpc(Atok, "create_direct_chat", {"other_id": C})
        conv2 = conv2 if isinstance(conv2, str) else conv2[0]
        st, r = http("POST", "/rest/v1/messages", Atok, {"conversation_id": conv, "sender_id": A, "type": "text", "content": "x"})
        check("report: silent block stops reporter<->target DM (existing block logic)", st >= 400, st)
        conv = conv2
        p2 = f"{conv}/{int(time.time()*1000)}_{A[:8]}.jpg"
        http("POST", f"/storage/v1/object/chat-media/{p2}", Atok, b"\xff\xd8\xff a", {"Content-Type": "image/jpeg"})
        st, m2 = http("POST", "/rest/v1/messages", Atok, {"conversation_id": conv, "sender_id": A, "type": "image",
                                                          "media_url": p2, "content": ""}, {"Prefer": "return=representation"})
        check("settings: shielded sender's media auto-protected", st == 201 and m2[0]["protected"] is True, f"{st}")
        st, m3 = http("POST", "/rest/v1/messages", Atok, {"conversation_id": conv, "sender_id": A, "type": "text",
                                                          "content": "regression: text still works"}, {"Prefer": "return=representation"})
        check("regression: normal text message unaffected", st == 201 and m3[0]["protected"] is False, st)
        st, chats = rpc(Atok, "my_chats", {})
        check("regression: my_chats works", st == 200 and len(chats) >= 2, st)
        st, _ = rpc(Atok, "my_channels", {})
        check("regression: my_channels works", st == 200, st)
        st, _ = rpc(Atok, "my_communities", {})
        check("regression: my_communities works", st == 200, st)
    finally:
        ids = [u[0] for u in users.values()]
        if ids:
            q = ",".join(f"'{i}'" for i in ids)
            # تنظيف ملفات الاختبار من التخزين
            if SERVICE:
                rows = sql(f"""select bucket_id, name from storage.objects where owner in ({q})
                               or (bucket_id='shield-quarantine' and name like any (select id::text||'/%' from shield_cases where reporter in ({q})))""")
                for r in rows:
                    req = urllib.request.Request(f"{BASE}/storage/v1/object/{r['bucket_id']}",
                        data=json.dumps({"prefixes": [r["name"]]}).encode(), method="DELETE",
                        headers={"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}", "Content-Type": "application/json"})
                    try: urllib.request.urlopen(req, timeout=30).read()
                    except Exception: pass
            sql(f"""delete from messages where content like '%Wasl Shield%' and conversation_id in (
                     select conversation_id from conversation_participants where user_id in (select user_id from app_admins))
                     and created_at > now() - interval '2 hours';
                   delete from conversations c where not exists (select 1 from conversation_participants p where p.conversation_id=c.id
                     and p.user_id not in ({q}) and p.user_id <> public.official_id('support')) and c.kind='chat' and not c.is_group
                     and exists (select 1 from conversation_participants p where p.conversation_id=c.id and p.user_id in ({q}));
                   delete from conversations c where exists (select 1 from conversation_participants p where p.conversation_id=c.id and p.user_id in ({q}))
                     and not exists (select 1 from conversation_participants p where p.conversation_id=c.id and p.user_id not in ({q}) and p.user_id not in (select id from app_official))
                     and c.kind in ('chat','saved') and not c.is_group;
                   delete from app_admins where user_id in ({q});
                   delete from auth.users where id in ({q});""")
    ok = sum(1 for r in results if r[1]); print(f"\n{ok}/{len(results)} passed")
    json.dump([{"test": n, "pass": p, "detail": str(d)[:200]} for n, p, d in results],
              open("/tmp/shield_results.json", "w"), ensure_ascii=False, indent=1)
    sys.exit(0 if ok == len(results) else 1)


if __name__ == "__main__":
    main()
