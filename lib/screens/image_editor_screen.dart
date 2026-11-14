import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../services/image_edit_service.dart';

/// محرر الصورة قبل الإرسال (المرحلة 8 — 0.20.0): قص بنِسَب، تدوير، رسم حر،
/// ونص فوق الصورة — كله على الجهاز بلا أي رفع قبل قبولك النهائي.
///
/// الناتج يُلتقط من لوحة العرض (RepaintBoundary) ثم يُحوَّل JPEG محلياً
/// عبر ImageEditService — الفشل يعيد PNG الأصلي ولا يمنع الإرسال.
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({super.key, required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;

  /// يفتح المحرر ويعيد البايتات النهائية (null = تخطي دون تعديل)
  static Future<Uint8List?> open(BuildContext context, Uint8List bytes,
      {String fileName = 'image.jpg'}) async {
    if (kIsWeb) return bytes; // الويب يرسل مباشرة كما هو
    return Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => ImageEditorScreen(bytes: bytes, fileName: fileName)),
    );
  }

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  // أبعاد الصورة الأصلية (لملاءمة الطبقة داخل الإطار)
  int _imgW = 0;
  int _imgH = 0;

  // التدوير (أرباع دورة 90 درجة)
  int _quarterTurns = 0;

  // نسبة القص: null = حر
  double? _cropRatio;
  static const _ratios = <(String, double?)>[
    ('حر', null),
    ('1:1', 1.0),
    ('3:4', 3 / 4),
    ('16:9', 16 / 9),
  ];

  // الرسم الحر — الألوان المشتركة على مستوى الملف أسفل الشاشة
  bool _drawMode = false;
  Color _penColor = Colors.white;
  final List<_Stroke> _strokes = [];

  // طبقة النص (طبقة واحدة قابلة للسحب والإزالة)
  String? _text;
  Color _textColor = Colors.white;
  Offset _textOffset = Offset.zero; // إزاحة مركز الطبقة داخل إطار الصورة
  bool _textDragMode = false;

  final _boundaryKey = GlobalKey();
  final _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    _decodeDims();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _decodeDims() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _imgW = frame.image.width;
        _imgH = frame.image.height;
      });
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  bool get _ready => _imgW > 0;

  // ---------- أدوات ----------

  void _rotate() {
    HapticFeedback.selectionClick();
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
  }

  void _undoStroke() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  Future<void> _addText() async {
    final ctrl = TextEditingController(text: _text ?? '');
    final color = await showDialog<(String, Color)?>(
      context: context,
      builder: (ctx) => _TextDialog(controller: ctrl, initialColor: _textColor),
    );
    ctrl.dispose();
    if (color == null) return;
    setState(() {
      if (color.$1.isEmpty) {
        _text = null; // نص فارغ = إزالة الطبقة
      } else {
        _text = color.$1;
        _textColor = color.$2;
        _textDragMode = true;
        if (_textOffset == Offset.zero) _textOffset = const Offset(0, -60);
      }
    });
  }

  // ---------- الالتقاط والإرسال ----------

  Future<void> _submit() async {
    final bctx = _boundaryKey.currentContext;
    if (bctx == null) return Navigator.pop(context, widget.bytes);
    try {
      final box = bctx.findRenderObject()! as RenderRepaintBoundary;
      final image = await box.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return Navigator.pop(context, widget.bytes);
      final png = data.buffer.asUint8List();
      // تحويل JPEG محلياً على عزل حسابي (صور كبيرة قد تتأخر)
      final out = await compute(_pngToJpegTask, png);
      if (!mounted) return;
      Navigator.pop(context, out);
    } catch (_) {
      // الفشل يهبط للسلوك السابق: إرسال الصورة كما هي
      if (mounted) Navigator.pop(context, widget.bytes);
    }
  }

  static Future<Uint8List> _pngToJpegTask(Uint8List png) =>
      ImageEditService.pngToJpeg(png);

  // ---------- البناء ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121319),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121319),
        foregroundColor: Colors.white,
        title: const Text('تحرير الصورة', style: TextStyle(fontSize: 17)),
        actions: [
          TextButton.icon(
            onPressed: _ready ? _submit : null,
            icon: const Icon(Icons.check_rounded, color: Colors.white),
            label: const Text('إرسال',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _ready ? _editor() : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _editor() {
    return SafeArea(
      child: Column(children: [
        Expanded(child: _frame()),
        _toolbar(),
      ]),
    );
  }

  /// الإطار: نسبة القص تُطبَّق على منطقة العرض، والصورة داخلها بالتدوير
  /// والتحريك (عند القص) أو الرسم المباشر (في وضع القلم)
  Widget _frame() {
    return LayoutBuilder(builder: (context, cons) {
      final maxW = cons.maxWidth;
      final maxH = cons.maxHeight;
      var frameW = maxW;
      var frameH = maxH;
      if (_cropRatio != null) {
        if (maxW / maxH > _cropRatio!) {
          frameW = maxH * _cropRatio!;
        } else {
          frameH = maxW / _cropRatio!;
        }
      }
      return Center(
        child: RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            width: frameW,
            height: frameH,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.white24, width: _cropRatio != null ? 1 : 0),
            ),
            child: ClipRect(
              child: InteractiveViewer(
                transformationController: _transform,
                // في وضع القلم أو سحب النص نوقف التحريك لصالح الرسم
                panEnabled: !_drawMode && !_textDragMode,
                scaleEnabled: !_drawMode && !_textDragMode,
                boundaryMargin: const EdgeInsets.all(80),
                minScale: 0.5,
                maxScale: 4,
                child: _imageLayer(frameW, frameH),
              ),
            ),
          ),
        ),
      );
    });
  }

  /// طبقة الصورة: الصورة بدورانها + الرسم والنص فوقها داخل الدوران نفسه
  /// (يلتصقان بمحتوى الصورة ويحركان ويكبران معها)
  Widget _imageLayer(double frameW, double frameH) {
    final angle = _quarterTurns * math.pi / 2;
    // ملاءمة أولية: الصورة تظهر كاملة داخل الإطار منذ البداية
    final fit = _imgW > 0
        ? math.min(frameW / _imgW, frameH / _imgH)
        : 1.0;
    final layerW = _imgW * fit;
    final layerH = _imgH * fit;
    return SizedBox(
      width: layerW,
      height: layerH,
      child: Transform.rotate(
        angle: angle,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Image.memory(widget.bytes,
                  fit: BoxFit.contain, gaplessPlayback: true),
            ),
            Positioned.fill(
              child: GestureDetector(
                onPanStart: _drawMode ? (d) => _startStroke(d.localPosition) : null,
                onPanUpdate: _drawMode ? (d) => _extendStroke(d.localPosition) : null,
                onPanEnd: _drawMode ? (_) => _endStroke() : null,
                child: CustomPaint(painter: _StrokePainter(_strokes), size: Size.infinite),
              ),
            ),
            if (_text != null)
              Positioned.fill(
                child: GestureDetector(
                  // السحب للنص فقط في وضع سحبه — والبقية للتكبير/التحريك
                  onPanUpdate: _textDragMode
                      ? (d) {
                          final s = _transform.value.getMaxScaleOnAxis();
                          final k = s > 0 ? d.delta.dx / s : d.delta.dx;
                          final ky = s > 0 ? d.delta.dy / s : d.delta.dy;
                          setState(() => _textOffset =
                              Offset(_textOffset.dx + k, _textOffset.dy + ky));
                        }
                      : null,
                  child: IgnorePointer(
                    ignoring: !_textDragMode,
                    child: Align(
                      alignment: Alignment.center,
                      child: Transform.translate(
                        offset: _textOffset,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _text!,
                            style: TextStyle(
                                color: _textColor,
                                fontSize: 22,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- الرسم ----------

  void _startStroke(Offset p) {
    setState(() => _strokes.add(_Stroke(color: _penColor, points: [p])));
  }

  void _extendStroke(Offset p) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.points.add(p));
  }

  void _endStroke() {}

  // ---------- شريط الأدوات ----------

  Widget _toolbar() {
    return Container(
      color: const Color(0xFF1B1C25),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_drawMode) _penRow(),
          _mainRow(),
          _ratioRow(),
        ]),
      ),
    );
  }

  Widget _mainRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _toolButton(
          icon: Icons.rotate_right_rounded,
          label: 'تدوير',
          active: false,
          onTap: _rotate,
        ),
        _toolButton(
          icon: Icons.draw_outlined,
          label: 'رسم',
          active: _drawMode,
          onTap: () => setState(() {
            _drawMode = !_drawMode;
            _textDragMode = false;
          }),
        ),
        if (_strokes.isNotEmpty)
          _toolButton(icon: Icons.undo_rounded, label: 'تراجع', active: false, onTap: _undoStroke)
        else
          _toolSpacer(),
        _toolButton(
          icon: Icons.text_fields_rounded,
          label: _text == null ? 'نص' : 'تعديل النص',
          active: _textDragMode,
          onTap: _addText,
        ),
        if (_text != null)
          _toolButton(
            icon: Icons.close_rounded,
            label: 'إزالة النص',
            active: false,
            onTap: () => setState(() => _text = null),
          )
        else
          _toolSpacer(),
      ]),
    );
  }

  Widget _penRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final c in _penColors) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _penColor = c);
            },
            customBorder: const CircleBorder(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                    color: _penColor == c ? Colors.white : Colors.white30,
                    width: _penColor == c ? 2.5 : 1),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _ratioRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final (label, ratio) in _ratios) ...[
          const SizedBox(width: 6),
          ChoiceChip(
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
            selected: _cropRatio == ratio,
            onSelected: (_) => setState(() => _cropRatio = ratio),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ]),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? WaslColors.teal.withValues(alpha: 0.25) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? WaslColors.teal : Colors.white70, size: 22),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: active ? WaslColors.teal : Colors.white60, fontSize: 10.5)),
        ]),
      ),
    );
  }

  Widget _toolSpacer() => const SizedBox(width: 48, height: 46);
}

class _Stroke {
  _Stroke({required this.color, required this.points});
  final Color color;
  final List<Offset> points;
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (final p in s.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => old.strokes != strokes;
}

/// ألوان القلم والنص المشتركة (على مستوى الملف تصلها الشاشة والحوار)
const _penColors = <Color>[
  Colors.white,
  Colors.black,
  Colors.redAccent,
  Colors.blueAccent,
  Colors.greenAccent,
  Colors.yellowAccent,
];

/// حوار إدخال النص واختيار لونه (المتحكم مملوك للشاشة المستدعية)
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.controller, this.initialColor = Colors.white});
  final TextEditingController controller;
  final Color initialColor;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  TextEditingController get _ctrl => widget.controller;
  late Color _color = widget.initialColor;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surfaceAlt,
      title: const Text('نص على الصورة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'اكتب النص…', counterText: ''),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final c in _penColors) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => setState(() => _color = c),
              customBorder: const CircleBorder(),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _color == c ? WaslColors.teal : Colors.white30,
                      width: _color == c ? 2.5 : 1),
                ),
              ),
            ),
          ],
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_ctrl.text.trim(), _color)),
          child: const Text('تم'),
        ),
      ],
    );
  }
}
