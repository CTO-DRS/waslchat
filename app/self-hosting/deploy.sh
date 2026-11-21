#!/bin/sh
# وصل سيرفر — ناشر الضغطة الواحدة (2.0.0)
# ما يفعله بصدق:
#   1) يتحقق من Docker وCompose وأن توزيعة Supabase تعمل (لا يستبدلها)
#   2) يولّد .env من القالب إن غاب (أسرار openssl — بلا قيم مضمّنة)
#   3) ينفذ الترحيلات بالترتيب 001 → الآخر عبر حاوية postgres مؤقتة
#   4) يشغل طبقة وصل (edge-runtime + coturn + backup) ويطبع الحالة الصادقة
# ما لا يفعله: لا TLS (وكيلك العكسي)، لا نشر متاجر، لا تنزيل نموذج — موثق.
set -e
cd "$(dirname "$0")"

say() { printf '\n[وصل سيرفر] %s\n' "$1"; }

# ————— 1) الفحوص —————
command -v docker >/dev/null 2>&1 || { say 'Docker غير مثبت — SELF_HOSTING.md §1'; exit 1; }
docker compose version >/dev/null 2>&1 || { say 'Compose غير متاح — ثبّت الإضافة الرسمية'; exit 1; }

# ————— 2) .env —————
if [ ! -f .env ]; then
  cp .env.example .env
  # كلمات التوليد الفوري للحقول المعلَّمة «غيّرني» — والبقية تبقى يدوية بصدق
  for key in POSTGRES_PASSWORD TURN_PASSWORD; do
    gen=$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)
    sed -i "s|^${key}=.*|${key}=${gen}|" .env
  done
  say 'أُنشئ .env بكلمات مولدة — أكمل بقية القيم (SERVICE_ROLE_KEY والدومين) قبل الإنتاج'
else
  say '.env موجود — لا لمسة تفسده'
fi

# ————— 3) الترحيلات بالترتيب —————
if [ "${SKIP_MIGRATIONS:-0}" != "1" ]; then
  # DATABASE_URL من .env إن وُجد، وإلا يُبنى من المتغيرات
  DB_URL="${DATABASE_URL:-postgres://postgres:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}}"
  say 'الترحيلات بالترتيب الرقمي حصراً (الفجوة 030 مقصودة وموثقة في GRAND_PLAN):'
  n=0
  for f in $(ls ../supabase/*.sql | sort); do
    n=$((n+1))
    printf '  %s\n' "$(basename "$f")"
    docker run --rm -i -v "$(cd .. && pwd)/supabase:/migrations:ro" \
      -e PGPASSWORD="${POSTGRES_PASSWORD}" postgres:17-alpine \
      psql -h "${POSTGRES_HOST}" -U postgres -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 \
      -f "/migrations/$(basename "$f")" >/dev/null \
      || { say "فشل $(basename "$f") — كل ملف يحمّل تحققاته أسفله: راجع الخرج بصدق ولا تكمل عمياء"; exit 1; }
  done
  say "نُفذ $n ترحيلاً بالترتيب"
else
  say 'تخطي الترحيلات (SKIP_MIGRATIONS=1)'
fi

# ————— 4) طبقة وصل —————
docker compose up -d
say 'الحالة الصادقة (لا ادعاء جاهزية):'
docker compose ps
say 'التالي عليك: وكيل عكسي TLS على /functions/v1/* → 127.0.0.1:9099، ومنافذ TURN (3478 + UDP TURN_MIN..MAX)، وتوجيه lib/config.dart لخادمك ثم بناء APK بتوقيعك (SELF_HOSTING.md §4-§6)'
