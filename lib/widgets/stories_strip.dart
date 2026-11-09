import 'package:flutter/material.dart';

import '../services/story_service.dart';
import '../theme.dart';
import 'common.dart';
import '../screens/story_composer_screen.dart';
import '../screens/story_viewer_screen.dart';

/// شريط الحالات أعلى قائمة المحادثات: «حالتي» + حلقات جهات الاتصال النشطة.
/// الحلقة المتدرجة = لم تُشاهد بعد، والرمادية = تمت المشاهدة.
class StoriesStrip extends StatefulWidget {
  const StoriesStrip({super.key});

  @override
  State<StoriesStrip> createState() => StoriesStripState();
}

class StoriesStripState extends State<StoriesStrip> {
  List<StoryItem> _mine = [];
  List<_AuthorGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// يُستدعى من شاشة المحادثات عند كل تحديث للقائمة
  Future<void> refresh() async {
    await StoryService.loadSeen();
    final mine = await StoryService.mine();
    final feed = await StoryService.feed();
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _groups = _groupByAuthor(feed);
      _loading = false;
    });
  }

  /// يجمع حالات كل كاتب في مجموعة، والأحدث أولاً
  static List<_AuthorGroup> _groupByAuthor(List<StoryItem> feed) {
    final map = <String, List<StoryItem>>{};
    for (final s in feed) {
      (map[s.authorId] ??= []).add(s);
    }
    final groups = map.entries.map((e) {
      final items = e.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return _AuthorGroup(
        authorId: e.key,
        name: e.value.first.authorName,
        avatar: e.value.first.authorAvatar,
        stories: items,
      );
    }).toList()
      ..sort((a, b) => b.stories.last.createdAt.compareTo(a.stories.last.createdAt));
    return groups;
  }

  Future<void> _openMine() async {
    if (_mine.isEmpty) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const StoryComposerScreen()));
    } else {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => StoryViewerScreen(stories: _mine, mine: true)));
    }
    if (mounted) refresh();
  }

  Future<void> _openAuthor(_AuthorGroup g) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => StoryViewerScreen(stories: g.stories)));
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: _loading
          ? const Center(child: SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)))
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              children: [
                _MineTile(count: _mine.length, onTap: _openMine),
                for (final g in _groups)
                  _AuthorTile(
                    group: g,
                    allSeen: g.stories.every((s) => StoryService.seen.contains(s.id)),
                    onTap: () => _openAuthor(g),
                  ),
                if (_groups.isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8, top: 26),
                    child: Text('حالات جهات اتصالك تظهر هنا',
                        style: TextStyle(
                            color: context.wasl.textFaint, fontSize: 12.5)),
                  ),
              ],
            ),
    );
  }
}

class _AuthorGroup {
  _AuthorGroup({
    required this.authorId,
    required this.name,
    this.avatar,
    required this.stories,
  });
  final String authorId;
  final String name;
  final String? avatar;
  final List<StoryItem> stories;
}

class _MineTile extends StatelessWidget {
  const _MineTile({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: count > 0 ? WaslColors.teal : context.wasl.border,
                    width: 2),
              ),
              child: CircleAvatar(
                radius: 25,
                backgroundColor: count > 0
                    ? WaslColors.indigo
                    : context.wasl.glassStrong,
                child: Icon(count > 0 ? Icons.visibility_outlined : Icons.add,
                    color: Colors.white, size: 22),
              ),
            ),
            PositionedDirectional(
              bottom: -2,
              end: -2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: WaslColors.gradient,
                  border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
                child: const Icon(Icons.add, size: 13, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('حالتي',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: context.wasl.textSecondary)),
        ]),
      ),
    );
  }
}

class _AuthorTile extends StatelessWidget {
  const _AuthorTile(
      {required this.group, required this.allSeen, required this.onTap});
  final _AuthorGroup group;
  final bool allSeen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: allSeen
                  ? null
                  : const LinearGradient(
                      colors: [WaslColors.indigo, WaslColors.teal, WaslColors.violet],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft),
              border: allSeen
                  ? Border.all(color: context.wasl.border, width: 2)
                  : null,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: UserAvatar(
                  name: group.name,
                  url: group.avatar,
                  radius: 22,
                  color: allSeen ? context.wasl.border : WaslColors.indigo),
            ),
          ),
          const SizedBox(height: 6),
          Text(group.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: context.wasl.textSecondary)),
        ]),
      ),
    );
  }
}
