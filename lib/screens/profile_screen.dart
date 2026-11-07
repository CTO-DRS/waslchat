import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
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
                    child: Text('@$_username', style: const TextStyle(color: Colors.white60))),
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
                const Text('صورتك واسمك ونبذتك يراها أي مستخدم في وصل.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
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
