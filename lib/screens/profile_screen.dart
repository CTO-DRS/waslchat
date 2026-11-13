import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/username_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// تعديل الملف الشخصي: الصورة والاسم الظاهر والنبذة
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final String _me = supabase.auth.currentUser!.id;
  String _username = '';
  String? _avatar;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final p = await supabase
          .from('profiles')
          .select('username, display_name, bio, avatar_url')
          .eq('id', _me)
          .single();
      if (!mounted) return;
      setState(() {
        _username = (p['username'] ?? '') as String;
        _name.text = (p['display_name'] ?? '') as String;
        _bio.text = (p['bio'] ?? '') as String;
        _avatar = p['avatar_url'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _snack('تعذّر تحميل الملف الشخصي');
    }
  }

  Future<void> _pickAvatar() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (x == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await x.readAsBytes();
      final png = x.name.toLowerCase().endsWith('.png');
      final path = '$_me/${DateTime.now().millisecondsSinceEpoch}.${png ? 'png' : 'jpg'}';
      final store = supabase.storage.from('avatars');
      await store.uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: png ? 'image/png' : 'image/jpeg'));
      final url = store.getPublicUrl(path);
      final old = _avatar;
      await supabase.from('profiles').update({'avatar_url': url}).eq('id', _me);
      if (old != null && old.contains('/avatars/$_me/')) {
        final oldPath = old.substring(old.indexOf('/avatars/') + '/avatars/'.length);
        store.remove([oldPath]).ignore();
      }
      if (mounted) setState(() => _avatar = url);
    } catch (_) {
      _snack('تعذّر رفع الصورة');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    final old = _avatar;
    if (old == null) return;
    try {
      await supabase.from('profiles').update({'avatar_url': null}).eq('id', _me);
      if (old.contains('/avatars/$_me/')) {
        final oldPath = old.substring(old.indexOf('/avatars/') + '/avatars/'.length);
        supabase.storage.from('avatars').remove([oldPath]).ignore();
      }
      if (mounted) setState(() => _avatar = null);
    } catch (_) {
      _snack('تعذّر حذف الصورة');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('اكتب اسمك');
      return;
    }
    setState(() => _saving = true);
    try {
      final bio = _bio.text.trim();
      await supabase.from('profiles').update({
        'display_name': name,
        'bio': bio.isEmpty ? null : bio,
      }).eq('id', _me);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _snack('تعذّر الحفظ');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// تغيير اسم المستخدم: فحص توفر حي + حفظ عبر الخادم (مرة كل 24 ساعة)
  Future<void> _editUsername() async {
    final ctrl = TextEditingController(text: _username);
    final formKey = GlobalKey<FormState>();
    bool? available;
    bool checking = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          backgroundColor: context.surfaceAlt,
          title: const Text('اسم المستخدم'),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: ctrl,
                prefixText: '@',
                autovalidateMode: AutovalidateMode.disabled,
                validator: (v) => UsernameService.validationError(v ?? ''),
                onChanged: (v) {
                  setSheet(() {
                    available = null;
                    checking = false;
                  });
                },
              ),
              const SizedBox(height: 8),
              Text('رابطك العام: ${UsernameService.profileLink(ctrl.text.trim().isEmpty ? _username : UsernameService.normalize(ctrl.text))}',
                  style: TextStyle(fontSize: 12, color: context.textTertiary)),
              if (checking)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final err = UsernameService.validationError(ctrl.text);
                if (err != null) {
                  formKey.currentState?.validate();
                  return;
                }
                setSheet(() => checking = true);
                final okAv = await UsernameService.available(ctrl.text);
                setSheet(() {
                  checking = false;
                  available = okAv;
                });
              },
              child: const Text('فحص التوفر'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: available == true
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final newName = UsernameService.normalize(ctrl.text);
    ctrl.dispose();
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final u = await UsernameService.set(newName);
      if (!mounted) return;
      setState(() => _username = u);
      _snack('صار اسمك @$u');
    } catch (e) {
      _snack(UsernameService.errorLabel(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyProfileLink() async {
    final link = UsernameService.profileLink(_username);
    await Clipboard.setData(ClipboardData(text: link));
    _snack('نُسخ رابط ملفك: $link');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Stack(children: [
                    UserAvatar(name: _name.text, url: _avatar, radius: 56),
                    PositionedDirectional(
                      bottom: 0,
                      end: 0,
                      child: Material(
                        color: WaslColors.teal,
                        shape: const CircleBorder(),
                        child: IconButton(
                          onPressed: _uploading ? null : _pickAvatar,
                          icon: _uploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.photo_camera_outlined, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                ),
                if (_avatar != null)
                  Center(
                    child: TextButton(
                        onPressed: _removeAvatar, child: const Text('إزالة الصورة')),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _editUsername,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('@$_username',
                            style: TextStyle(color: context.textTertiary)),
                        const SizedBox(width: 4),
                        Icon(Icons.edit_outlined,
                            size: 14, color: context.textFaint),
                      ]),
                    ),
                  ),
                ),
                if (_username.isNotEmpty)
                  Center(
                    child: TextButton.icon(
                      onPressed: _copyProfileLink,
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: Text('نسخ رابط waslchat.app/@$_username',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'الاسم الظاهر'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bio,
                  maxLength: 140,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(labelText: 'نبذة عنك'),
                ),
                const SizedBox(height: 8),
                Text('صورتك واسمك ونبذتك يراها أي مستخدم في وصل.',
                    style: TextStyle(color: context.textFaint, fontSize: 12)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
                ),
              ],
            ),
    );
  }
}
