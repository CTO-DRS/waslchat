-- وصل شات 0.1.9: إخراج سر الـWebhook من مصدر دالة الإشعارات (إغلاق ثغرة أمنية)
--
-- المشكلة: سر x-webhook-secret كان مضمّناً نصاً داخل مصدر notify_push، وpg_proc يقرؤه
-- أي مستخدم مصادق — فيستطيع مناداة دالتي push وmedia-cleanup مباشرة (إزعاج/تكلفة/إساءة).
-- الحل: السر في جدول داخل مخطط private (غير مكشوف عبر PostgREST)، والدالتان تقرؤانه منه.
--
-- ملاحظة: إن أعدت تشغيل 013_files_video_cleanup.sql بعد هذا الملف فسيعيد جدولة الوسائط
-- بالسر داخل أمر cron — أعد تشغيل هذا الملف بعدها.

create schema if not exists private;
revoke all on schema private from anon, authenticated;

create table if not exists private.webhook_secrets (
  name text primary key,
  value text not null
);

-- ترحيل قيمة السر الحالية من مصدر notify_push (مرة واحدة — يُتجاهل إن وُجد)
insert into private.webhook_secrets (name, value)
select 'push_webhook', substring(src from '''x-webhook-secret''\s*,\s*''([^'']+)''')
from (select prosrc as src from pg_proc where proname = 'notify_push' limit 1) s
where substring(src from '''x-webhook-secret''\s*,\s*''([^'']+)''') is not null
on conflict (name) do nothing;

do $$
declare secret text;
begin
  select value into secret from private.webhook_secrets where name = 'push_webhook';
  if secret is null or secret like '<%' then
    raise exception 'webhook secret not found: ضع السر يدوياً في private.webhook_secrets ثم أعد تشغيل الملف';
  end if;

  -- إعادة تعريف دالة الإشعارات: تقرأ السر من الجدول — لا سر في المصدر بعد اليوم
  execute $fn$
    create or replace function public.notify_push() returns trigger
    language plpgsql security definer set search_path = public, extensions as $body$
    declare s text;
    begin
      select value into s from private.webhook_secrets where name = 'push_webhook';
      perform net.http_post(
        url := 'https://hplzbillnbdjtufazrlp.supabase.co/functions/v1/push',
        body := jsonb_build_object('type','INSERT','table','messages','record',to_jsonb(new)),
        headers := jsonb_build_object('Content-Type','application/json','x-webhook-secret',s)
      );
      return new;
    end $body$;
  $fn$;
end $$;

revoke all on function public.notify_push() from public, anon, authenticated;

-- جدولة تنظيف الوسائط عبر دالة وسيطة: أمر cron لا يحمل السر بعد اليوم
create or replace function public.run_media_cleanup()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare s text;
begin
  select value into s from private.webhook_secrets where name = 'push_webhook';
  perform net.http_post(
    url := 'https://hplzbillnbdjtufazrlp.supabase.co/functions/v1/media-cleanup',
    headers := jsonb_build_object('Content-Type','application/json','x-webhook-secret',s),
    body := '{}'::jsonb
  );
end $$;

revoke all on function public.run_media_cleanup() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('wasl-media-cleanup');
exception when others then null; end $$;
select cron.schedule('wasl-media-cleanup', '7 * * * *', 'select public.run_media_cleanup()');

-- تحقق سريع بعد التشغيل: لا سر ظاهر في المصدر ولا في أمر cron
-- select prosrc from pg_proc where proname='notify_push';            -- يجب ألا يحتوي السر
-- select jobname, command from cron.job where jobname='wasl-media-cleanup'; -- نفس الشيء
