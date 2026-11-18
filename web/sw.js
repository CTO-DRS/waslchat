/* وصل شات — عامل الصفحة (Service Worker) — المرحلة 12 (0.28.0)
 *
 * ثلاث مهام صادقة بلا وعود:
 * 1) جعل التطبيق قابلاً للتثبيت PWA (المتصفحات تشترط عامل صفحة يمنكفetch
 *    كي يقدّم زر التثبيت أصلاً).
 * 2) فتح الواجهة دون اتصال: الواجهة وحدها تُفتح — الرسائل والمكالمات
 *    والتشفير اللحظي يحتاجون الشبكة حصراً، ولا نكذب على المستخدم بغير ذلك.
 * 3) استقبال الإشعارات الفورية (Web Push) وعرضها — الحمولة نص إشعار
 *    عام من دالة push (المحتوى المشفر لا يمر هنا إطلاقاً).
 */
const SHELL_CACHE = 'wasl-shell-v1';
const ASSET_CACHE = 'wasl-assets-v1';

/* قلب الواجهة فقط: مستندات وملفات الجذر — كلها network-first
 * كي لا يخدم التحديث القديم بعد نشر إصدار جديد أبداً. */
const SHELL_URLS = [
  './',
  'index.html',
  'manifest.json',
  'flutter_bootstrap.js',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(SHELL_CACHE)
      .then((c) => c.addAll(SHELL_URLS))
      .then(() => self.skipWaiting())
      .catch(() => {/* فشل التخزين المسبق لا يكسر التثبيت — يعيد المحاولة لاحقاً */})
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k !== SHELL_CACHE && k !== ASSET_CACHE)
            .map((k) => caches.delete(k))
        )
      )
      .then(() => self.clients.claim())
  );
});

/* الأصول الثابتة (خطوط وصور وأيقونات النظام): serve من الكاش فوراً
 * وتحديثه في الخلفية (stale-while-revalidate) — سريع ويتصحح ذاتياً. */
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // Supabase وغيرها لا تُمس

  if (req.mode === 'navigate') {
    // المستند: شبكة أولاً ثم الكاش ثم index.html — أحدث دائماً إن وصلنا
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put('./', copy));
          return res;
        })
        .catch(() =>
          caches
            .match('./')
            .then((r) => r || Response.error())
        )
    );
    return;
  }

  if (url.pathname.includes('/assets/') || url.pathname.includes('/canvaskit/')) {
    event.respondWith(
      caches.open(ASSET_CACHE).then(async (cache) => {
        const cached = await cache.match(req);
        const network = fetch(req)
          .then((res) => {
            if (res && res.ok) cache.put(req, res.clone());
            return res;
          })
          .catch(() => null);
        if (cached) {
          event.waitUntil(network);
          return cached;
        }
        const res = await network;
        return res || Response.error();
      })
    );
    return;
  }

  // بقية ملفات الجذر (bootstrap وmain.dart.js): شبكة أولاً ثم الكاش —
  // كود التطبيق لا يخدم قديماً أبداً إن توفرت الشبكة.
  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req).then((r) => r || Response.error()))
  );
});

/* الإشعارات الفورية: الحمولة {title, body, conversationId, kind} —
 * نص إشعار عام من الخادم (المحتوى المشفر لا يمر هنا إطلاقاً)، وأي
 * حمولة غريبة تُعرض عنواناً عاماً بلا ادعاء. */
self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }
  const title = typeof payload.title === 'string' && payload.title
    ? payload.title
    : 'وصل شات';
  const body = typeof payload.body === 'string' && payload.body
    ? payload.body
    : 'رسالة جديدة';
  const tag =
    typeof payload.conversationId === 'string' && payload.conversationId
      ? payload.conversationId
      : 'wasl-generic';
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      tag,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      dir: 'rtl',
      lang: 'ar',
      data: { conversationId: payload.conversationId || null, kind: payload.kind || 'message' },
    })
  );
});

/* نقر الإشعار: تركيز نافذة موجودة أو فتح واحدة — بلا شاشات شبح */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      return self.clients.openWindow('./');
    })
  );
});

/* أمر تخطي الانتظار من التطبيق — تحديث أنظف بإعادة فتح واحدة */
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
