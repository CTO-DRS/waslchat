-- مُطبَّق على المشروع الحالي. لإعادة إنشائه في مشروع جديد استبدل القيم بين <>
create extension if not exists pg_net with schema extensions;
create or replace function public.notify_push() returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin
  perform net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/push',
    body := jsonb_build_object('type','INSERT','table','messages','record',to_jsonb(new)),
    headers := jsonb_build_object('Content-Type','application/json','x-webhook-secret','<WEBHOOK_SECRET>')
  );
  return new;
end $$;
revoke all on function public.notify_push() from public, anon, authenticated;
drop trigger if exists messages_push on public.messages;
create trigger messages_push after insert on public.messages for each row execute function public.notify_push();
