import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/tone_service.dart';
import 'package:wasl_chat/services/tone_studio.dart';

Uint8List _sine(double sec, {int rate = 24000, double f = 440, double lead = 0.2}) {
  final n = ((sec + 2 * lead) * rate).round();
  final s = Int16List(n);
  final a = (lead * rate).round();
  for (var i = a; i < n - a; i++) {
    s[i] = (math.sin(2 * math.pi * f * i / rate) * 12000).round();
  }
  return ToneStudio.encodeWav(Pcm(s, rate));
}

void main() {
  group('ToneStudio', () {
    test('wav round trip', () {
      final w = _sine(0.5);
      final p = ToneStudio.decodeWav(w);
      expect(p.rate, 24000);
      expect(ToneStudio.encodeWav(p), w);
    });

    test('rejects non-wav', () {
      expect(() => ToneStudio.decodeWav(Uint8List.fromList(List.filled(50, 1))),
          throwsFormatException);
    });

    test('resample changes length', () {
      final p = ToneStudio.decodeWav(_sine(1, rate: 48000));
      expect(ToneStudio.resample(p).samples.length, closeTo(p.samples.length / 2, 2));
      final fast = ToneStudio.resample(p, toRate: 48000, factor: 2);
      expect(fast.samples.length, closeTo(p.samples.length / 2, 2));
    });

    test('trimSilence removes lead silence', () {
      final p = ToneStudio.decodeWav(_sine(0.5, lead: 0.5));
      final t = ToneStudio.trimSilence(p);
      expect(t.seconds, lessThan(0.6));
      expect(t.seconds, greaterThan(0.45));
    });

    test('compose voice + melody, order and cap', () {
      final out = ToneStudio.decodeWav(ToneStudio.compose(
          voiceWav: _sine(1), melodyWav: _sine(1, f: 880), voiceFirst: false));
      expect(out.seconds, greaterThan(1.9));
      expect(out.seconds, lessThanOrEqualTo(ToneStudio.maxSeconds));
      final long = ToneStudio.decodeWav(ToneStudio.compose(melodyWav: _sine(9)));
      expect(long.seconds, closeTo(ToneStudio.maxSeconds, 0.01));
      expect(() => ToneStudio.compose(), throwsStateError);
    });

    test('every effect yields audible audio', () {
      for (final fx in VoiceFx.values) {
        final out = ToneStudio.decodeWav(ToneStudio.compose(voiceWav: _sine(0.6), fx: fx));
        expect(out.samples.any((v) => v.abs() > 1000), isTrue, reason: fx.name);
      }
      final child = ToneStudio.decodeWav(ToneStudio.compose(voiceWav: _sine(1), fx: VoiceFx.child));
      expect(child.seconds, lessThan(0.8));
    });
  });

  group('ToneService', () {
    test('ids unique and default valid', () {
      final ids = ToneService.builtIn.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, contains(ToneService.defaultTone));
      expect(ToneService.normalize('nope'), ToneService.defaultTone);
    });

    test('custom tones decode and normalize', () {
      final list = ToneService.decodeCustom(
          '[{"id":"c_1","label":"x","hint":"y","uri":"content://a","path":"/p"}]');
      expect(list.single.isCustom, isTrue);
      expect(ToneService.normalizeIn('c_1', list), 'c_1');
      expect(ToneService.normalizeIn('c_2', list), ToneService.defaultTone);
      expect(ToneService.decodeCustom('garbage'), isEmpty);
    });

    test('channel ids', () {
      expect(ToneService.channelId('system'), 'messages');
      expect(ToneService.channelId('c_1'), 'msg_c_1_v1');
      expect(ToneService.reminderChannelId('wasl_calm'), 'rem_wasl_calm_v1');
    });
  });
}
