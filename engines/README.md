# محركات وصل النقية المفتوحة (v1.9.0)

ست حزم Dart نقية مُستخرجة من كود وصل شات حرفياً — بلا Flutter ولا شبكة ولا
أسرار — برخصة MIT موحدة، لتبني ثقة عربية **قابلة للتحقق** لا للادعاء:
«هذا ما يشفر رسائلك ويحسب تقويمك ويترجم ويقيس — اقرأه وشغّله بنفسك».

| الحزمة | ماذا تفعل | المصدر الحرفي |
|---|---|---|
| `wasl_ratchet` | Double Ratchet + X3DH ثلاثي + Ed25519 + ML-KEM-768 هجين | `lib/services/ratchet.dart` |
| `wasl_semantic` | البحث الدلالي المتجهي على الجهاز | `semantic_search_service.dart` + `smart_search_service.dart` |
| `wasl_hijri` | التقويم الهجري الحسابي | `lib/services/hijri_service.dart` |
| `wasl_translate` | الترجمة القاموسية المحلية | `local_translate_service.dart` + `local_ai_service.dart` |
| `wasl_model_gate` | تقييم تشغيل نموذج على الجهاز | `on_device_model_service.dart` |
| `wasl_voice_waves` | مستوى الصوت من إحصاءات WebRTC وكاشف «يتحدث» | مستوحى من `call_quality_service.dart` و`voice_room_service.dart` |

## التحقق محلياً

```sh
cd engines/wasl_ratchet && dart pub get && dart test   # وكل حزمة كذلك
```

## التحقق من خلو الأسرار

```sh
python3 scripts/scrub_engines.py
```

## دفعها كمستودعات مستقلة (بيد المالك)

كل مجلد هنا حزمة كاملة مستقلة — ينسخ إلى مستودعه العام كما هو بعد تشغيل
فحص الأسرار مرة أخيرة، مع `repository:` يُعدَّل إلى المستودع الجديد.

## لماذا قطع مجمّدة؟

المحركات هنا لقطات عند 1.9.0+71 تُحدَّث يدوياً عند تغيّر الأصل — لأن دمج
بناء التطبيق مع بناء الحزم يربط فتح المحركات بإيقاعات الإصدارات. البساطة
والاستقلالية أولوية الشفافية هنا، والاختبارات داخل كل حزمة تثبت سلامتها
بمعزل عن التطبيق.
