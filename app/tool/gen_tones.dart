// يولّد نغمات «وصل شات» الجاهزة من قطع الاستوديو بمحرّك الاستوديو نفسه.
// الاستخدام: dart run tool/gen_tones.dart <spec.json> <outDir>
// spec: [{"id":"wasl_x","voice":"v_orus"|null,"melody":"mel_classic"|null,"fx":"robot","speed":1.0,"voiceFirst":true}]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wasl_chat/services/tone_studio.dart';

void main(List<String> a) {
  final spec = jsonDecode(File(a[0]).readAsStringSync()) as List;
  for (final e in spec.cast<Map>()) {
    Uint8List? rd(String? id) =>
        id == null ? null : File('assets/tones/$id.wav').readAsBytesSync();
    final wav = ToneStudio.compose(
      voiceWav: rd(e['voice'] as String?),
      melodyWav: rd(e['melody'] as String?),
      voiceFirst: (e['voiceFirst'] as bool?) ?? true,
      speed: ((e['speed'] as num?) ?? 1.0).toDouble(),
      fx: VoiceFx.values.byName((e['fx'] as String?) ?? 'none'),
    );
    File('${a[1]}/${e['id']}.wav').writeAsBytesSync(wav);
    stdout.writeln(e['id']);
  }
}
