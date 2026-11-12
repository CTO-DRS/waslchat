import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/status_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// الحالات/القصص المشفّرة: شريط الحلقات في أعلى المحادثات + العارض الكامل + النشر
///
/// - الشريط: «حالتي» أولاً ثم أصحاب الحالات (حلقة متدرجة = بادج غير مقروء).
/// - العارض: صفحة كاملة بشرائط تقدم، تنقّل بالنقر يميناً/يساراً وتقدّم تلقائي،
///   تسجيل المشاهدة، قائمة المشاهدين وحذف الحالة لصاحبها.
/// - كل المحتوى يُفكّ على الجهاز فقط (StatusService)؛ 🔒 عند تعذر الفك.

/// شريط الحلقات الأفقي (يوضع أعلى قائمة المحادثات)
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.groups,
    required this.onTapMe,
    required this.onTapAuthor,
  });

  final List<Map<String, dynamic>> groups;
  final VoidCallback onTapMe;
  final ValueChanged<int> onTapAuthor; // فهرس المجموعة

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          final isMe = g['is_me'] == true;
          final count = (g['statuses'] as List).length;
          final seen = g['all_viewed'] == true;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 14),
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: isMe ? onTapMe : () => onTapAuthor(i),
              child: SizedBox(
                width: 72,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: (isMe || !seen) ? WaslColors.gradient : null,
                        color: seen && !isMe ? Colors.white24 : null,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).scaffoldBackgroundColor,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            UserAvatar(
                              name: (g['author_name'] ?? '') as String,
                              url: g['author_avatar'] as String?,
                              radius: 24,
                              color: isMe ? WaslColors.indigo : WaslColors.teal,
                            ),
                            if (isMe && count == 0)
                              PositionedDirectional(
                                bottom: -2,
                                end: -2,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: WaslColors.teal,
                                  ),
                                  child: const Icon(Icons.add,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isMe ? 'حالتي' : (g['author_name'] ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isMe || !seen ? FontWeight.w700 : FontWeight.w400,
                        color: isMe || !seen ? null : Colors.white54,
                      ),
                    ),
                    if (!isMe && count > 1)
                      Text('$count حالات',
                          style: const TextStyle(fontSize: 9, color: Colors.white38)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ورقة نشر حالة (نص أو صورة)
Future<void> showStatusComposer(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: WaslColors.darkSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => const _StatusComposer(),
  );
}

class _StatusComposer extends StatefulWidget {
  const _StatusComposer();

  @override
  State<_StatusComposer> createState() => _StatusComposerState();
}

class _StatusComposerState extends State<_StatusComposer> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _image;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _image = bytes;
      _error = null;
    });
  }

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_image != null) {
        await StatusService.publishImage(_image!);
      } else {
        await StatusService.publishText(_controller.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذّر نشر الحالة — تأكد من الاتصال وحاول مجدداً';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('حالة جديدة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: 'صورة من المعرض',
                icon: const Icon(Icons.image_outlined, color: WaslColors.teal),
                onPressed: _busy ? null : _pickImage,
              ),
              if (_image != null)
                IconButton(
                  tooltip: 'إزالة الصورة',
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: _busy ? null : () => setState(() => _image = null),
                ),
            ]),
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Image.memory(_image!, fit: BoxFit.cover),
                ),
              )
            else
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                maxLength: StatusService.maxTextChars,
                decoration:
                    const InputDecoration(hintText: 'بماذا تفكر اليوم؟'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: WaslColors.indigo),
              onPressed: _busy ||
                      (_image == null && _controller.text.trim().isEmpty)
                  ? null
                  : _publish,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 18),
              label: const Text('نشر الحالة'),
            ),
            const SizedBox(height: 6),
            const Text('مشفّرة بين الطرفين — تظهر لشركاء محادثاتك الفردية 24 ساعة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

/// العارض الكامل: مجموعة (قائمة الحالات) تبدأ من فهرس معين
Future<bool> openStatusViewer(
    BuildContext context, List<Map<String, dynamic>> groups, int initialIndex) async {
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => StatusViewerScreen(groups: groups, initial: initialIndex)),
  );
  return r == true;
}

class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({super.key, required this.groups, required this.initial});

  final List<Map<String, dynamic>> groups;
  final int initial;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  late final List<_FlatStatus> _flat;
  late final PageController _page;
  int _i = 0;
  bool _changed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _flat = [
      for (var g = 0; g < widget.groups.length; g++)
        for (var s = 0; s < (widget.groups[g]['statuses'] as List).length; s++)
          _FlatStatus(group: g, index: s),
    ];
    _i = _flat.indexWhere((f) => f.group == widget.initial);
    if (_i < 0) _i = 0;
    _page = PageController(initialPage: _i);
    _onShown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _group => widget.groups[_flat[_i].group];
  Map<String, dynamic> get _status =>
      (_group['statuses'] as List)[_flat[_i].index] as Map<String, dynamic>;
  bool get _isMine => _group['is_me'] == true;

  /// عند عرض حالة غيري غير المشهودة: تسجيل مشاهدة + تحديث محلي
  void _onShown() {
    _timer?.cancel();
    _timer = Timer(_status['kind'] == 'image' ? _imgDur : _txtDur, _next);
    if (!_isMine && _status['viewed'] != true) {
      final sid = _status['status_id'] as String;
      _status['viewed'] = true;
      StatusService.markViewed(sid);
      final g = _group;
      g['all_viewed'] = (g['statuses'] as List).every((s) => s['viewed'] == true);
      _changed = true;
    }
  }

  static const _txtDur = Duration(seconds: 6);
  static const _imgDur = Duration(seconds: 8);

  void _go(int i) {
    if (i < 0 || i >= _flat.length) {
      Navigator.pop(context, _changed);
      return;
    }
    setState(() {
      _i = i;
      _page.jumpToPage(i);
    });
    _onShown();
  }

  void _next() => _go(_i + 1);
  void _prev() => _go(_i - 1);

  Future<void> _deleteMine() async {
    final sid = _status['status_id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WaslColors.darkSurface,
        title: const Text('حذف الحالة؟'),
        content: const Text('ستُحذف من جميع من يشاهدها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StatusService.delete(sid);
      _changed = true;
      if (!mounted) return;
      setState(() => widget.groups[_flat[_i].group]['statuses'].removeAt(_flat[_i].index));
      final sts = widget.groups[_flat[_i].group]['statuses'] as List;
      if (sts.isEmpty) {
        if (widget.groups.length == 1) {
          Navigator.pop(context, true);
        } else {
          setState(() => widget.groups.removeAt(_flat[_i].group));
          _rebuildFlat();
        }
      } else {
        _rebuildFlat();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر الحذف')));
      }
    }
  }

  void _rebuildFlat() {
    final newFlat = [
      for (var g = 0; g < widget.groups.length; g++)
        for (var s = 0; s < (widget.groups[g]['statuses'] as List).length; s++)
          _FlatStatus(group: g, index: s),
    ];
    if (newFlat.isEmpty) {
      Navigator.pop(context, true);
      return;
    }
    final g = _flat[_i].group.clamp(0, widget.groups.length - 1);
    final s = _flat[_i].index;
    var target = newFlat.indexWhere((f) => f.group == g && f.index == s);
    if (target < 0) target = newFlat.indexWhere((f) => f.group == g);
    if (target < 0) target = 0;
    setState(() {
      _flat
        ..clear()
        ..addAll(newFlat);
      _i = target;
      _page.jumpToPage(target);
    });
    _onShown();
  }

  void _showViewers() {
    final sid = _status['status_id'] as String;
    showModalBottomSheet(
      context: context,
      backgroundColor: WaslColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: StatusService.viewers(sid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()));
          }
          final rows = snap.data ?? [];
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('شاهدها ${rows.length} ${rows.length == 1 ? 'شخص' : 'أشخاص'}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا مشاهدات بعد',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final p = rows[i]['profiles'] as Map<String, dynamic>?;
                      final name =
                          (p?['display_name'] ?? p?['username'] ?? 'مستخدم') as String;
                      return ListTile(
                        leading: UserAvatar(
                            name: name,
                            url: p?['avatar_url'] as String?,
                            radius: 18,
                            color: WaslColors.indigo),
                        title: Text(name),
                        trailing: Text(StatusService.ageText(rows[i]['viewed_at'] as String),
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      );
                    },
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) => _timer?.cancel(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _page,
          itemCount: _flat.length,
          onPageChanged: (i) {
            setState(() => _i = i);
            _onShown();
          },
          itemBuilder: (context, i) {
            final g = widget.groups[_flat[i].group];
            final s = (g['statuses'] as List)[_flat[i].index] as Map<String, dynamic>;
            final sts = g['statuses'] as List;
            final posInGroup = _flat[i].index;
            return Column(children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(children: [
                    // شرائط التقدم: قطاع لكل حالة من حالات هذا الصاحب
                    Expanded(
                      child: Row(
                        children: [
                          for (var j = 0; j < sts.length; j++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: LinearProgressIndicator(
                                  value: j < posInGroup
                                      ? 1
                                      : (j == posInGroup ? 0.35 : 0),
                                  minHeight: 3,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(children: [
                    UserAvatar(
                      name: (g['author_name'] ?? '') as String,
                      url: g['author_avatar'] as String?,
                      radius: 18,
                      color: _isMine ? WaslColors.indigo : WaslColors.teal,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((g['author_name'] ?? '') as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700)),
                          Text(StatusService.ageText(s['created_at'] as String),
                              style:
                                  const TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context, _changed)),
                  ]),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    // RTL: التالي يساراً والسابق يميناً
                    final isRtl = Directionality.of(context) == TextDirection.rtl;
                    final w = context.size?.width ?? MediaQuery.of(context).size.width;
                    final leftHalf = d.localPosition.dx < w / 2;
                    if (isRtl) {
                      if (leftHalf) {
                        _next();
                      } else {
                        _prev();
                      }
                    } else {
                      if (leftHalf) {
                        _prev();
                      } else {
                        _next();
                      }
                    }
                  },
                  child: Center(child: _body(s)),
                ),
              ),
              if (_isMine)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      FilledButton.tonalIcon(
                        onPressed: _showViewers,
                        icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                        label: Text('${s['views_count'] ?? 0} مشاهدة'),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'حذف الحالة',
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.white12),
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: _deleteMine,
                      ),
                    ]),
                  ),
                )
              else
                const SizedBox(height: 18),
            ]);
          },
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> s) {
    if (s['kind'] == 'image') {
      return FutureBuilder<Uint8List?>(
        future: StatusService.decryptMedia(s),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 10),
              Text('جارٍ فك التشفير…', style: TextStyle(color: Colors.white54)),
            ]);
          }
          final bytes = snap.data;
          if (bytes == null) {
            return _locked();
          }
          return InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain),
          );
        },
      );
    }
    return FutureBuilder<String?>(
      future: StatusService.decryptText(s),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator(color: Colors.white);
        }
        final text = snap.data;
        if (text == null) return _locked();
        if (text.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: WaslColors.gradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, height: 1.7, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  Widget _locked() => const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline, color: Colors.white38, size: 44),
        SizedBox(height: 12),
        Text('تعذّر فك تشفير هذه الحالة على هذا الجهاز',
            style: TextStyle(color: Colors.white38)),
      ]);
}

class _FlatStatus {
  _FlatStatus({required this.group, required this.index});
  final int group;
  final int index;
}
