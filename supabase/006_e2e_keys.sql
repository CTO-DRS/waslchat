-- وصل شات 0.1.2: مفاتيح التشفير بين الطرفين — المرحلة 1 (المحادثات الخاصة)
-- شغّله في SQL Editor بعد 005_push_trigger.sql
--
-- كل جهاز يولّد زوج X25519: الخاص يبقى على الجهاز، والعام يُنشر هنا.
-- مفتاح المحادثة يُشتق عند الطرفين: HKDF(X25519(أنا, الآخر), salt = conversation_id)
-- فلا حاجة لجداول جديدة في هذه المرحلة، ولا تغيير على RLS
-- (المفتاح العام ليس سرياً، وكل مستخدم يحدّث صفّه هو فقط بسياسة "users update own profile").

alter table public.profiles
  add column if not exists identity_public_key text,
  add column if not exists key_fp text;

-- قيود طول (تسمح بـ NULL لمن لم يولّد مفاتيحه بعد)
do $$ begin
  alter table public.profiles add constraint profiles_identity_key_check
    check (identity_public_key is null or char_length(identity_public_key) between 40 and 64);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.profiles add constraint profiles_key_fp_check
    check (key_fp is null or char_length(key_fp) between 8 and 64);
exception when duplicate_object then null; end $$;
