import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/album_service.dart';
import '../theme.dart';

/// معاينة الألبوم المتعدد قبل الإرسال (المرحلة 8 — 0.20.0):
/// عرض متسلسل للمختارات حتى 10 وسائط مع إمكانية إزالة أي قطعة،
/// ثم تعيد القائمة النهائية للشاشة المستدعية للإرسال المشفر كالعادة.
class AlbumPreviewScreen extends StatefulWidget {
  const AlbumPreviewScreen({super.key, required this.files});
  final List<XFile> files;

  /// يفتح المعاينة ويعيد المختارات النهائية (فارغة = إلغاء)
  static Future<List<XFile>?> open(BuildContext context, List<XFile> files) {
    if (files.isEmpty) return Future.value(null);
    return Navigator.push<List<XFile>>(
      context,
      MaterialPageRoute(builder: (_) => AlbumPreviewScreen(files: files.take(AlbumService.maxItems).toList())),
    );
  }

  @override
  State<AlbumPreviewScreen> createState() => _AlbumPreviewScreenState();
}

class _AlbumPreviewScreenState extends State<AlbumPreviewScreen> {
  late final List<XFile> _files = List.of(widget.files);
  final _picker = ImagePicker();
  final _pageCtrl = PageController();
  int _current = 0;
  bool _loadingMore = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMore() async {
    final room = AlbumService.maxItems - _files.length;
    if (room <= 0) return;
    setState(() => _loadingMore = true);
    try {
      final picked = await _picker.pickMultiImage(limit: room, maxWidth: 1600, imageQuality: 80);
      if (picked.isNotEmpty) {
        setState(() {
          _files.addAll(picked);
          _current = _files.length - 1;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _files.length;
    final room = AlbumService.maxItems - count;
    return Scaffold(
      backgroundColor: const Color(0xFF121319),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121319),
        foregroundColor: Colors.white,
        title: Text('ألبوم — ${AlbumService.counterLabel(count)}',
            style: const TextStyle(fontSize: 16)),
        actions: [
          if (room > 0)
            IconButton(
              tooltip: 'إضافة وسائط ($room متاح)',
              onPressed: _loadingMore ? null : _addMore,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          TextButton(
            onPressed: count == 0
                ? null
                : () => Navigator.pop(context, List.of(_files)),
            child: Text('إرسال ${count == 0 ? '' : '($count)'}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: count == 0
          ? Center(
              child: Text('لا وسائط — اضغط إضافة لاختيار الصور',
                  style: TextStyle(color: Colors.white54)))
          : Column(children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: count,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, i) => FutureBuilder<Uint8List>(
                    future: _files[i].readAsBytes(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Center(
                        child: InteractiveViewer(
                          maxScale: 4,
                          child: Image.memory(snap.data!, fit: BoxFit.contain),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                    for (var i = 0; i < count; i++)
                      GestureDetector(
                        onTap: () => setState(() => _current = i),
                        child: Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _current ? WaslColors.teal : Colors.white24,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _files.removeAt(_current);
                        if (_current >= _files.length && _current > 0) {
                          _current = _files.length - 1;
                        }
                      }),
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      label: const Text('إزالة هذه',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}
