import 'dart:math' as math;
import 'dart:typed_data';

/// محرّك «استوديو الصوت» (1.12.0): يدمج صوت «وصل شات» ولحناً وتسجيلك
/// في ملف WAV واحد على الجهاز — بلا أي خادم. كل الدوال نقية وقابلة للاختبار.
class Pcm {
  final Int16List samples;
  final int rate;
  const Pcm(this.samples, this.rate);
  double get seconds => samples.length / rate;
}

/// مؤثرات الصوت في الاستوديو (تُطبّق على الصوت وحده لا على اللحن)
enum VoiceFx { none, child, giant, robot, echo, radio, space }

class ToneStudio {
  static const rate = 24000;
  static const maxSeconds = 6.0;

  /// قراءة WAV (PCM 16-bit). القنوات المتعددة تُدمج إلى قناة واحدة.
  static Pcm decodeWav(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('not wav');
    }
    var p = 12;
    int channels = 1, sr = rate, bits = 16;
    Uint8List? data;
    while (p + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(p, p + 4));
      var size = bd.getUint32(p + 4, Endian.little);
      final start = p + 8;
      if (start + size > bytes.length) size = bytes.length - start;
      if (id == 'fmt ') {
        channels = bd.getUint16(start + 2, Endian.little);
        sr = bd.getUint32(start + 4, Endian.little);
        bits = bd.getUint16(start + 14, Endian.little);
      } else if (id == 'data') {
        data = bytes.sublist(start, start + size);
      }
      p = start + size + (size.isOdd ? 1 : 0);
    }
    if (data == null || bits != 16 || channels < 1) {
      throw const FormatException('unsupported wav');
    }
    final dv = ByteData.sublistView(data);
    final frames = data.length ~/ (2 * channels);
    final out = Int16List(frames);
    for (var i = 0; i < frames; i++) {
      var s = 0;
      for (var c = 0; c < channels; c++) {
        s += dv.getInt16((i * channels + c) * 2, Endian.little);
      }
      out[i] = s ~/ channels;
    }
    return Pcm(out, sr);
  }

  static Uint8List encodeWav(Pcm pcm) {
    final n = pcm.samples.length * 2;
    final b = ByteData(44 + n);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + n, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, pcm.rate, Endian.little);
    b.setUint32(28, pcm.rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, n, Endian.little);
    for (var i = 0; i < pcm.samples.length; i++) {
      b.setInt16(44 + i * 2, pcm.samples[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  /// إعادة أخذ العينات (خطّي). [factor] > 1 أسرع وأحدّ، < 1 أبطأ وأعمق.
  static Pcm resample(Pcm src, {int toRate = rate, double factor = 1.0}) {
    final step = src.rate / toRate * factor;
    if ((step - 1.0).abs() < 1e-9) return Pcm(Int16List.fromList(src.samples), toRate);
    final len = (src.samples.length / step).floor();
    final out = Int16List(math.max(0, len));
    for (var i = 0; i < len; i++) {
      final x = i * step;
      final j = x.floor();
      final f = x - j;
      final a = src.samples[j];
      final b = j + 1 < src.samples.length ? src.samples[j + 1] : a;
      out[i] = (a + (b - a) * f).round();
    }
    return Pcm(out, toRate);
  }

  /// قص الصمت من البداية والنهاية (عتبة نسبية لأعلى قمة)
  static Pcm trimSilence(Pcm p, {double threshold = 0.03}) {
    final s = p.samples;
    if (s.isEmpty) return p;
    var peak = 0;
    for (final v in s) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    if (peak == 0) return Pcm(Int16List(0), p.rate);
    final th = peak * threshold;
    var a = 0, b = s.length - 1;
    while (a < b && s[a].abs() < th) {
      a++;
    }
    while (b > a && s[b].abs() < th) {
      b--;
    }
    final pad = (p.rate * 0.02).round();
    a = math.max(0, a - pad);
    b = math.min(s.length - 1, b + pad);
    return Pcm(Int16List.fromList(s.sublist(a, b + 1)), p.rate);
  }

  /// تطبيق مؤثر على صوت (قبل التطبيع)
  static Pcm applyFx(Pcm p, VoiceFx fx) {
    switch (fx) {
      case VoiceFx.none:
        return p;
      case VoiceFx.child:
        // نبرة طفولية: رفع الطبقة ~45%
        return resample(p, toRate: p.rate, factor: 1.45);
      case VoiceFx.giant:
        return resample(p, toRate: p.rate, factor: 0.74);
      case VoiceFx.robot:
        return _robot(p);
      case VoiceFx.echo:
        return _echo(p, delay: 0.16, decay: 0.45, taps: 3);
      case VoiceFx.radio:
        return _radio(p);
      case VoiceFx.space:
        return _echo(_robot(p, freq: 38, mix: 0.55), delay: 0.22, decay: 0.5, taps: 4);
    }
  }

  /// صوت آلي: تعديل حلقي + تقطيع دقة خفيف
  static Pcm _robot(Pcm p, {double freq = 64, double mix = 0.85}) {
    final out = Int16List(p.samples.length);
    for (var i = 0; i < out.length; i++) {
      final m = math.sin(2 * math.pi * freq * i / p.rate);
      var v = p.samples[i] * ((1 - mix) + mix * m);
      v = (v / 1024).roundToDouble() * 1024; // تقطيع خفيف
      out[i] = v.round().clamp(-32768, 32767);
    }
    return Pcm(out, p.rate);
  }

  /// صدى: نسخ متأخرة متناقصة، ويطول الملف بقدرها
  static Pcm _echo(Pcm p, {double delay = 0.16, double decay = 0.45, int taps = 3}) {
    final d = (delay * p.rate).round();
    final out = Float64List(p.samples.length + d * taps);
    for (var i = 0; i < p.samples.length; i++) {
      var g = 1.0;
      for (var t = 0; t <= taps; t++) {
        out[i + d * t] += p.samples[i] * g;
        g *= decay;
      }
    }
    var peak = 1.0;
    for (final v in out) {
      if (v.abs() > peak) peak = v.abs();
    }
    final k = peak > 32767 ? 32767 / peak : 1.0;
    return Pcm(Int16List.fromList([for (final v in out) (v * k).round()]), p.rate);
  }

  /// راديو/لاسلكي: ترشيح نطاق (300–3200 هرتز) مع تشبّع خفيف
  static Pcm _radio(Pcm p) {
    List<double> biquad(List<double> x, double f0, double q, bool high) {
      final w = 2 * math.pi * f0 / p.rate;
      final alpha = math.sin(w) / (2 * q);
      final c = math.cos(w);
      final b0 = high ? (1 + c) / 2 : (1 - c) / 2;
      final b1 = high ? -(1 + c) : 1 - c;
      final b2 = b0;
      final a0 = 1 + alpha, a1 = -2 * c, a2 = 1 - alpha;
      final y = List<double>.filled(x.length, 0);
      double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
      for (var i = 0; i < x.length; i++) {
        final v = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
        x2 = x1;
        x1 = x[i];
        y2 = y1;
        y1 = v;
        y[i] = v;
      }
      return y;
    }

    var x = [for (final v in p.samples) v / 32768.0];
    x = biquad(x, 300, 0.707, true);
    x = biquad(x, 3200, 0.707, false);
    final out = Int16List(x.length);
    for (var i = 0; i < x.length; i++) {
      final v = math.atan(x[i] * 3) / math.atan(3.0);
      out[i] = (v * 30000).round().clamp(-32768, 32767);
    }
    return Pcm(out, p.rate);
  }

  static Pcm silence(double seconds, [int r = rate]) =>
      Pcm(Int16List((seconds * r).round()), r);

  /// تطبيع القمة إلى [target] من أقصى مستوى
  static Pcm normalize(Pcm p, {double target = 0.89}) {
    var peak = 1;
    for (final v in p.samples) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    final g = 32767 * target / peak;
    final out = Int16List(p.samples.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = (p.samples[i] * g).round().clamp(-32768, 32767);
    }
    return Pcm(out, p.rate);
  }

  static Pcm fadeOut(Pcm p, {double seconds = 0.06}) {
    final n = math.min(p.samples.length, (seconds * p.rate).round());
    final out = Int16List.fromList(p.samples);
    for (var i = 0; i < n; i++) {
      final k = out.length - n + i;
      out[k] = (out[k] * (1 - (i + 1) / n)).round();
    }
    return Pcm(out, p.rate);
  }

  static Pcm concat(List<Pcm> parts) {
    final total = parts.fold<int>(0, (a, p) => a + p.samples.length);
    final out = Int16List(total);
    var o = 0;
    for (final p in parts) {
      out.setRange(o, o + p.samples.length, p.samples);
      o += p.samples.length;
    }
    return Pcm(out, rate);
  }

  /// يدمج الصوت واللحن (أي منهما اختياري) بالترتيب والسرعة المطلوبين،
  /// ويقص الناتج لـ[maxSeconds] ويطبّعه.
  static Uint8List compose({
    Uint8List? voiceWav,
    Uint8List? melodyWav,
    bool voiceFirst = true,
    double speed = 1.0,
    double gap = 0.08,
    VoiceFx fx = VoiceFx.none,
  }) {
    Pcm? prep(Uint8List? w, {bool trim = true, VoiceFx f = VoiceFx.none}) {
      if (w == null) return null;
      var p = resample(decodeWav(w), factor: speed);
      if (trim) p = trimSilence(p);
      if (p.samples.isNotEmpty) p = applyFx(p, f);
      return p.samples.isEmpty ? null : normalize(p);
    }

    final v = prep(voiceWav, f: fx);
    final m = prep(melodyWav, trim: false);
    final parts = <Pcm>[];
    final order = voiceFirst ? [v, m] : [m, v];
    for (final p in order) {
      if (p == null) continue;
      if (parts.isNotEmpty) parts.add(silence(gap));
      parts.add(p);
    }
    if (parts.isEmpty) throw StateError('empty');
    var out = concat(parts);
    final max = (maxSeconds * rate).round();
    if (out.samples.length > max) {
      out = Pcm(Int16List.fromList(out.samples.sublist(0, max)), rate);
    }
    out = fadeOut(normalize(out, target: 0.92));
    return encodeWav(out);
  }
}
