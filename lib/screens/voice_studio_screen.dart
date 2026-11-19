import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/tone_service.dart';
import '../services/tone_studio.dart';
import '../theme.dart';
import '../widgets/wasl_sheet.dart';

/// استوديو الصوت (1.12.0): مكتبة النغمات، وصناعة نغمتك من صوت ولحن
/// أو من تسجيلك، ونغماتك المحفوظة. كل شيء يُصنع على جهازك.
class VoiceStudioScreen extends StatefulWidget {
  const VoiceStudioScreen({super.key});

  @override
  State<VoiceStudioScreen> createState() => _VoiceStudioScreenState();
}

class _VoiceStudioScreenState extends State<VoiceStudioScreen> {
  static const _mine = '__mine__';
  static const _none = '__none__';

  String _voice = ToneService.studioVoices.first.id;
  String _melody = ToneService.studioMelodies.first.id;
  bool _voiceFirst = true;
  double _speed = 1.0;
  VoiceFx _fx = VoiceFx.none;

  Uint8List? _recorded;
  final _rec = AudioRecorder();
  bool _recording = false;
  Timer? _recTimer;
  bool _busy = false;

  @override
  void dispose() {
    _recTimer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  void _snack(String m, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), action: action));
  }

  Future<Uint8List?> _asset(String id) async {
    if (id == _none) return null;
    if (id == _mine) return _recorded;
    final d = await rootBundle.load('assets/tones/$id.wav');
    return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  }

  Future<Uint8List?> _compose() async {
    if (_voice == _none && _melody == _none) {
      _snack('اختر صوتاً أو لحناً على الأقل');
      return null;
    }
    if (_voice == _mine && _recorded == null) {
      _snack('سجّل صوتك أولاً');
      return null;
    }
    try {
      return ToneStudio.compose(
        voiceWav: await _asset(_voice),
        melodyWav: await _asset(_melody),
        voiceFirst: _voiceFirst,
        speed: _speed,
        fx: _fx,
      );
    } catch (_) {
      _snack('تعذّر تجهيز النغمة، جرّب اختياراً آخر');
      return null;
    }
  }

  Future<void> _listen() async {
    setState(() => _busy = true);
    final wav = await _compose();
    if (wav != null) await ToneService.playFile(await ToneService.writeDraft(wav));
    if (mounted) setState(() => _busy = false);
  }

  static String _fxLabel(VoiceFx f) => switch (f) {
        VoiceFx.none => 'بلا مؤثر',
        VoiceFx.child => 'طفولي',
        VoiceFx.giant => 'عملاق',
        VoiceFx.robot => 'روبوت',
        VoiceFx.echo => 'صدى',
        VoiceFx.radio => 'لاسلكي',
        VoiceFx.space => 'فضائي',
      };

  Future<void> _pickVoice(String id) async {
    setState(() => _voice = id);
    if (id == _none || id == _mine) return;
    try {
      final d = await rootBundle.load('assets/tones/$id.wav');
      await ToneService.playFile(await ToneService.writeDraft(
          d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes)));
    } catch (_) {}
  }

  String _describe() {
    String v = _voice == _mine
        ? 'صوتك'
        : _voice == _none
            ? ''
            : ToneService.studioVoices.firstWhere((e) => e.id == _voice).label;
    String m = _melody == _none
        ? ''
        : ToneService.studioMelodies.firstWhere((e) => e.id == _melody).label;
    if (v.isNotEmpty && _fx != VoiceFx.none) v = '$v (${_fxLabel(_fx)})';
    final parts = (_voiceFirst ? [v, m] : [m, v]).where((e) => e.isNotEmpty);
    return parts.join(' + ');
  }

  Future<void> _save() async {
    final wav = await _compose();
    if (wav == null || !mounted) return;
    final ctrl = TextEditingController(text: 'نغمتي ${ToneService.custom.value.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم النغمة'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 24),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (name == null) return;
    setState(() => _busy = true);
    final t = await ToneService.saveCustom(wav, name, _describe());
    if (!mounted) return;
    setState(() => _busy = false);
    if (t == null) {
      _snack('تعذّر حفظ النغمة على هذا الجهاز');
      return;
    }
    _snack('حُفظت «${t.label}» في نغماتي',
        action: SnackBarAction(
            label: 'اجعلها للكل',
            onPressed: () => ToneService.setGlobal(t.id)));
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecord();
      return;
    }
    if (!await _rec.hasPermission()) {
      _snack('اسمح للتطبيق باستخدام الميكروفون لتسجيل نغمتك');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/tone_rec.wav';
    try {
      await _rec.start(
          const RecordConfig(
              encoder: AudioEncoder.wav, sampleRate: ToneStudio.rate, numChannels: 1),
          path: path);
    } catch (_) {
      _snack('تعذّر بدء التسجيل');
      return;
    }
    setState(() => _recording = true);
    _recTimer = Timer(const Duration(seconds: 4), _stopRecord);
  }

  Future<void> _stopRecord() async {
    _recTimer?.cancel();
    if (!_recording) return;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      final pcm = ToneStudio.trimSilence(ToneStudio.decodeWav(bytes));
      if (pcm.samples.length < ToneStudio.rate * 0.2) {
        _snack('التسجيل قصير جداً، أعد المحاولة بصوت أوضح');
        return;
      }
      setState(() {
        _recorded = ToneStudio.encodeWav(pcm);
        _voice = _mine;
      });
      _listen();
    } catch (_) {
      _snack('تعذّر قراءة التسجيل');
    }
  }

  // ------------------------------------------------------------------ UI

  Widget _chips(List<(String, String)> items, String selected, ValueChanged<String> on) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, label) in items)
          ChoiceChip(
            label: Text(label),
            selected: selected == id,
            selectedColor: WaslColors.teal.withValues(alpha: 0.25),
            onSelected: (_) => on(id),
          ),
      ]),
    );
  }

  Widget _hero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          WaslColors.indigo.withValues(alpha: 0.30),
          WaslColors.teal.withValues(alpha: 0.18),
        ]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ValueListenableBuilder<String>(
        valueListenable: ToneService.global,
        builder: (_, g, __) => Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                gradient: WaslColors.gradient, shape: BoxShape.circle),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('نغمتك لكل المحادثات',
                  style: TextStyle(fontSize: 12.5, color: context.textFaint)),
              const SizedBox(height: 2),
              Text(ToneService.byId(g).label,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
          IconButton.filledTonal(
            onPressed: () => ToneService.preview(g),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ]),
      ),
    );
  }

  Widget _toneTile(WaslTone t) {
    return ValueListenableBuilder<String>(
      valueListenable: ToneService.global,
      builder: (_, g, __) {
        final on = g == t.id;
        return SheetTile(
          icon: switch (t.group) {
            ToneGroup.voice => Icons.record_voice_over_rounded,
            ToneGroup.melody => Icons.music_note_rounded,
            ToneGroup.custom => Icons.auto_awesome_rounded,
            ToneGroup.system => Icons.phone_android_rounded,
          },
          color: on ? WaslColors.teal : WaslColors.indigo,
          title: t.label,
          subtitle: t.hint,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'استمع',
              icon: const Icon(Icons.play_circle_outline_rounded),
              onPressed: () => ToneService.preview(t.id),
            ),
            if (on)
              const Icon(Icons.check_circle_rounded, color: WaslColors.teal)
            else if (t.isCustom)
              PopupMenuButton<String>(
                onSelected: (a) => _customAction(t, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'use', child: Text('اجعلها للكل')),
                  PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
          ]),
          onTap: () {
            ToneService.preview(t.id);
            ToneService.setGlobal(t.id);
          },
        );
      },
    );
  }

  Future<void> _customAction(WaslTone t, String a) async {
    if (a == 'use') {
      await ToneService.setGlobal(t.id);
    } else if (a == 'delete') {
      await ToneService.deleteCustom(t.id);
      _snack('حُذفت «${t.label}»');
    } else if (a == 'rename') {
      final ctrl = TextEditingController(text: t.label);
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('اسم جديد'),
          content: TextField(controller: ctrl, autofocus: true, maxLength: 24),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ')),
          ],
        ),
      );
      if (name != null) await ToneService.renameCustom(t.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (r) => WaslColors.gradient.createShader(r),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Text('استوديو الصوت', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
        children: [
          _hero(context),
          const SheetSectionLabel('اصنع نغمتك'),
          GlassGroup([
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Text('الصوت', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final sec in const ['الأصلية', 'رجالية', 'نسائية', 'طفولية']) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: Text(sec,
                      style: TextStyle(fontSize: 12, color: context.textFaint)),
                ),
                _chips([
                  for (final v in ToneService.studioVoices.where((v) => v.hint == sec))
                    (v.id, v.label),
                ], _voice, _pickVoice),
              ],
              _chips([
                if (_recorded != null) (_mine, 'صوتي'),
                (_none, 'بلا صوت'),
              ], _voice, _pickVoice),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: Text('للصوت الطفولي أو الآلي اختر أي صوت ثم المؤثر المناسب.',
                    style: TextStyle(fontSize: 11.5)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: OutlinedButton.icon(
                  onPressed: _toggleRecord,
                  icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: _recording ? Colors.redAccent : WaslColors.teal),
                  label: Text(_recording
                      ? 'جارٍ التسجيل… اضغط للإيقاف'
                      : _recorded == null
                          ? 'سجّل صوتك (حتى 4 ثوانٍ)'
                          : 'أعد تسجيل صوتك'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Text('مؤثر الصوت', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              _chips([
                for (final f in VoiceFx.values) (f.name, _fxLabel(f)),
              ], _fx.name, (id) => setState(() => _fx = VoiceFx.values.byName(id))),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Text('اللحن', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              _chips([
                for (final m in ToneService.studioMelodies) (m.id, m.label),
                (_none, 'بلا لحن'),
              ], _melody, (id) => setState(() => _melody = id)),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Text('الترتيب', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('الصوت أولاً')),
                    ButtonSegment(value: false, label: Text('اللحن أولاً')),
                  ],
                  selected: {_voiceFirst},
                  onSelectionChanged: (s) => setState(() => _voiceFirst = s.first),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Text('النبرة والسرعة', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 0.88, label: Text('أعمق')),
                    ButtonSegment(value: 1.0, label: Text('طبيعية')),
                    ButtonSegment(value: 1.12, label: Text('أسرع')),
                    ButtonSegment(value: 1.25, label: Text('أحدّ')),
                  ],
                  selected: {_speed},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _speed = s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _listen,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('استمع'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.bookmark_add_rounded),
                      label: const Text('احفظ النغمة'),
                    ),
                  ),
                ]),
              ),
            ]),
          ]),
          ValueListenableBuilder<List<WaslTone>>(
            valueListenable: ToneService.custom,
            builder: (_, list, __) => list.isEmpty
                ? const SizedBox.shrink()
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SheetSectionLabel('نغماتي'),
                    GlassGroup([for (final t in list) _toneTile(t)]),
                  ]),
          ),
          for (final sec in ToneService.sectionOrder.where((x) => x != 'نغماتي')) ...[
            SheetSectionLabel(sec == 'الأصلية' ? '«وصل شات» الأصلية' : sec == 'ألحان بلا كلام' ? sec : 'أصوات $sec'),
            GlassGroup([
              for (final t in ToneService.builtIn.where((t) => ToneService.sectionOf(t) == sec))
                _toneTile(t)
            ]),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
            child: Text(
                'اضغط أي نغمة لتسمعها وتجعلها لكل المحادثات. ولنغمة خاصة بمحادثة: افتحها ثم «المزيد» ثم «نغمة الإشعار».',
                style: TextStyle(fontSize: 12, color: context.textFaint)),
          ),
        ],
      ),
    );
  }
}
