# wasl_model_fetch — تنزيل موثق لنموذج على الجهاز

المحرك النقي الثامن من محركات وصل (بعد wasl_ratchet وwasl_semantic وwasl_voice_waves
وwasl_hijri وwasl_translate وwasl_model_gate). يغلق **التدفق الصادق** الموثق في
`docs/ON_DEVICE_LLM.md` وGRAND_PLAN_3 المرحلة 18: نموذج يُنزَّل فقط بموافقة صريحة،
من مصدر موثق ببصمة، ويُعتمد فقط بعد تحقق إلزامي.

## العقد الصادق

1. **بلا شبكة داخلية**: دفق البايتات يُحقن من الخارج (`ByteStreamFactory`) —
   الاختبارات تمرر بايتات محلية والتطبيق يمرر `HttpClient` الخاص به.
2. **بصمة إلزامية**: كل `ModelSource` يحمل بصمة SHA-256 منشورة من ناشر النموذج
   (HuggingFace يوفرها في `lfs.oid` عبر API الرسمي) — ملف لا تطابق بصمته لا
   يُعتمد أبداً ويُمحى فوراً.
3. **كتابة ذرية**: التنزيل في `<id>.part` والاعتماد إعادة تسمية إلى `<id>.gguf`
   فقط بعد نجاح التحقق — فلا يوجد لحظة يوهم فيها نصف ملف بأنه نموذج جاهز.
4. **بصمة على الطاير**: تُحسب أثناء التنزيل (بلا قراءة ثانية كاملة) — SHA-256
   نقي مطبق يدوياً بلا أي اعتمادية، بمتجهات اختبار محسوبة خارجياً بـpython
   hashlib (مستقلة عن هذا التنفيذ).
5. **حذف كامل**: `delete()` يمسح النهائي والمؤقت والبصمة المدونة بلا أثر.

## الواجهة

```dart
final fetcher = ModelFetcher(modelsDir: dir, streamFactory: myDownloader);
final result = await fetcher.fetch(source, onProgress: (p) => show(p.percent));
if (result.ok) { /* الجاهزية عبر isReady والتحقق الصارم عبر verifyFull */ }
```

## اختبار

```bash
dart test
```
