/// MURA — Journal page: searchable entries + memory strip.
///
/// Assumes the shared api singleton from ../api.dart exposes:
///   listJournalEntries() -> List`<JournalEntry`>
///   searchJournalEntries(String query) -> List`<JournalEntry`>
///   createJournalEntry(Map`<String, dynamic`>) -> JournalEntry
///   deleteJournalEntry(int id) -> Future`<void`>
///   listMemories() -> List`<MemoryItem`>
/// And ../models.dart types:
///   JournalEntry {id, title, body, mood, createdAt}
///   MemoryItem   {id, title, date, photo}
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../refresh_bus.dart';
import '../models.dart';
import '../theme.dart'; // ignore: unused_import -- shared tokens land here later.

// Obsidian & Amber palette (#0D0B09 family backgrounds, amber accents).

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _fmtDateTime(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day} - $hh:$mm';
}

String _fmtDay(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A2117),
      content: Text(msg, style: TextStyle(color: MuraPalette.of(context).text)),
    ));
}

class _MoodMeta {
  final String emoji;
  final Color color;
  const _MoodMeta(this.emoji, this.color);
}

_MoodMeta _moodMeta(String? mood, MuraPalette pal) {
  switch (mood) {
    case 'great':
      return _MoodMeta('😄', pal.amber);
    case 'good':
      return _MoodMeta('🙂', pal.teal);
    case 'neutral':
      return _MoodMeta('😐', pal.textDim);
    case 'low':
      return _MoodMeta('😞', pal.coral);
    default:
      return _MoodMeta('📝', pal.textDim);
  }
}

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> with AppRefreshListener {
  MuraPalette get _pal => MuraPalette.of(context);
  List<JournalEntry>? _entries;
  bool _busy = false;
  String? _err;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<MemoryItem>? _memories;
  bool _searchOpen = false;
  int? _expandedStoryId;
  String _sort = 'top';
  String? _status;
  final Set<int> _engagingIds = <int>{};

  /// Which list the page shows: the user's own journal entries (their
  /// journal — the default) or the community story feed. Saved entries
  /// were invisible before because only the story feed was ever listed.
  bool _showMine = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _loadEntries();
    _loadMemories();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadEntries();
    });
  }

  @override
  void onAppRefresh() {
    _loadEntries();
    _loadMemories();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final q = _search.text.trim();
      if (_showMine) {
        // The user's own entries — what the Write button creates.
        final mine =
            await api.journalEntries(search: q.isEmpty ? null : q);
        if (!mounted) return;
        setState(() {
          _entries = mine;
          _busy = false;
        });
        return;
      }
      final stories = await api.contentItems(
        type: 'journal_story',
        search: q.isEmpty ? null : q,
        sort: _sort,
        status: _status,
        pageSize: 200,
      );
      final items = stories
          .map((story) => JournalEntry(
                id: story.id,
                title: story.source.isEmpty ? 'A MURA story' : story.source,
                body: story.text,
                createdAt: story.createdAt,
                image: story.image,
                authorName:
                    story.tags.isEmpty ? 'MURA community' : story.tags.first,
                viewCount: story.viewCount,
                likeCount: story.likeCount,
                viewed: story.viewed,
                read: story.read,
                liked: story.liked,
                saved: story.saved,
              ))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _entries = items;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = friendlyError(e);
        _busy = false;
      });
    }
  }

  Future<void> _engage(
    JournalEntry entry, {
    bool read = false,
    bool like = false,
    bool save = false,
  }) async {
    // Community engagement endpoints only exist for stories — personal
    // entries have no like/save/read plumbing on the server.
    if (_showMine) return;
    if (_engagingIds.contains(entry.id)) return;
    setState(() => _engagingIds.add(entry.id));
    try {
      final ContentItem result = save
          ? await api.saveContent(entry.id)
          : like
              ? await api.likeContent(entry.id)
              : read
                  ? await api.readContent(entry.id)
                  : await api.viewContent(entry.id);
      if (!mounted || _entries == null) return;
      setState(() {
        _entries = _entries!
            .map((item) => item.id == entry.id
                ? item.copyWith(
                    viewCount: result.viewCount,
                    likeCount: result.likeCount,
                    viewed: result.viewed,
                    read: result.read,
                    liked: result.liked,
                    saved: result.saved,
                  )
                : item)
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) _toast(context, 'Could not update story activity');
    } finally {
      if (mounted) setState(() => _engagingIds.remove(entry.id));
    }
  }

  Future<void> _loadMemories() async {
    try {
      final items = await api.listMemories();
      if (!mounted) return;
      setState(() => _memories = items);
    } catch (_) {
      // Strip stays hidden when memories can't be fetched.
    }
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B140D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete entry?',
            style: TextStyle(
                color: _pal.text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('"${entry.title}" will be gone for good.',
            style: TextStyle(color: _pal.textDim, fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: _pal.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Color(0xFFFF8A80), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(
        () => _entries = _entries!.where((x) => x.id != entry.id).toList());
    try {
      await api.deleteJournalEntry(entry.id);
    } catch (_) {
      if (mounted) _toast(context, 'Could not delete entry');
      _loadEntries();
    }
  }

  Future<void> _openEditor() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171208),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _EntryEditorSheet(),
    );
    if (saved == true && mounted) {
      // A freshly saved entry is the user's own — jump straight to the
      // My Entries list so they SEE it (invisible saves were the bug).
      setState(() => _showMine = true);
      await _loadEntries();
      if (mounted) _toast(context, 'Entry saved ✨');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _showMine
                              ? 'Your private journal — write, reflect, keep.'
                              : 'A living feed of journeys, lessons, and turning points.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _searchOpen = !_searchOpen),
                    icon: Icon(
                      _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainer,
                    ),
                  ),
                ],
              ),
            ),
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                child: TextField(
                  controller: _search,
                  cursorColor: Theme.of(context).colorScheme.primary,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        _showMine ? 'Search your entries' : 'Search stories',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            _buildMineStoriesToggle(),
            _buildMemoryStrip(),
            if (!_showMine) _buildStoryFilters(),
            Expanded(
              child: RefreshIndicator(
                color: _pal.amber,
                backgroundColor: _pal.field,
                onRefresh: _loadEntries,
                child: _buildList(),
              ),
            ),
          ],
        ),
      ),
      // The editor sheet existed but nothing opened it — a journal app
      // you cannot write in is the definition of "not interactive".
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'journal-fab',
        onPressed: _openEditor,
        backgroundColor: _pal.amberDeep,
        foregroundColor: _pal.onAmber,
        elevation: 3,
        icon: const Icon(Icons.edit_outlined, size: 21),
        label: const Text('Write',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
      ),
    );
  }

  /// Journal vs community: your own entries are the page's primary content.
  Widget _buildMineStoriesToggle() {
    Widget side(String label, bool mine) {
      final selected = _showMine == mine;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_showMine == mine) return;
            setState(() {
              _showMine = mine;
              _expandedStoryId = null;
            });
            _loadEntries();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? _pal.amber.withValues(alpha: .16)
                  : _pal.field,
              borderRadius: BorderRadius.horizontal(
                left: mine ? const Radius.circular(13) : Radius.zero,
                right: mine ? Radius.zero : const Radius.circular(13),
              ),
              border: Border.all(
                  color: selected ? _pal.amber : _pal.stroke),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _pal.amber : _pal.textDim,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .4,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          side('MY ENTRIES', true),
          side('STORIES', false),
        ],
      ),
    );
  }

  Widget _buildStoryFilters() {
    Widget chip(String label, String? value, {String? status}) {
      final selected = status != null ? _status == status : _sort == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            if (status != null) {
              _status = _status == status ? null : status;
            } else {
              _sort = value!;
            }
          });
          _loadEntries();
        },
        selectedColor: _pal.amber.withValues(alpha: .25),
        labelStyle: TextStyle(
          color: selected
              ? _pal.amber
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: selected ? _pal.amber : _pal.stroke),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        children: [
          chip('Top', 'top'),
          const SizedBox(width: 8),
          chip('Latest', 'newest'),
          const SizedBox(width: 8),
          chip('Most viewed', 'most_viewed'),
          const SizedBox(width: 8),
          chip('Most liked', 'most_liked'),
          const SizedBox(width: 8),
          chip('Unread', null, status: 'unread'),
          const SizedBox(width: 8),
          chip('Viewed', null, status: 'viewed'),
          const SizedBox(width: 8),
          chip('Liked', null, status: 'liked'),
        ],
      ),
    );
  }

  Widget _buildMemoryStrip() {
    final mems = _memories;
    if (mems == null || mems.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('MEMORIES',
                    style: TextStyle(
                        color: _pal.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
                const Spacer(),
                Text('${mems.length}',
                    style: TextStyle(color: _pal.textDim, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: mems.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                if (i == mems.length) return _addMemoryTile();
                return _MemoryCard(memory: mems[i]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _addMemoryTile() {
    return GestureDetector(
      onTap: () => _toast(context, 'Photo upload coming soon'),
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: _pal.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _pal.stroke),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 22, color: _pal.amber.withValues(alpha: .85)),
            const SizedBox(height: 6),
            Text('Add photo',
                style: TextStyle(color: _pal.textDim, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_busy && _entries == null) {
      return Center(child: CircularProgressIndicator(color: _pal.amber));
    }
    if (_err != null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
          child: Column(
            children: [
              Icon(Icons.cloud_off_rounded, color: _pal.textDim, size: 36),
              const SizedBox(height: 12),
              Text('Something broke: ${_err!}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _pal.textDim, fontSize: 12.5)),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _loadEntries,
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _pal.amber)),
                child: Text('Retry', style: TextStyle(color: _pal.amber)),
              ),
            ],
          ),
        ),
      ]);
    }
    final entries = _entries ?? const [];
    if (entries.isEmpty) {
      final searching = _search.text.trim().isNotEmpty;
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
          child: Column(
            children: [
              Icon(
                  searching
                      ? Icons.search_off_rounded
                      : (_showMine
                          ? Icons.edit_note_rounded
                          : Icons.menu_book_rounded),
                  color: _pal.textDim.withValues(alpha: .7),
                  size: 38),
              const SizedBox(height: 12),
              Text(
                  searching
                      ? 'No matches'
                      : (_showMine ? 'Nothing written yet' : 'No stories yet'),
                  style: TextStyle(
                      color: _pal.text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                searching
                    ? 'Try a different word or phrase.'
                    : (_showMine
                        ? 'Tap Write and put today\'s lesson on record.'
                        : 'Stories are curated through TheFeeder.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: _pal.textDim, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _EntryCard(
        entry: entries[i],
        personal: _showMine,
        expanded: _expandedStoryId == entries[i].id,
        onDelete: () => _deleteEntry(entries[i]),
        onLike: () => _engage(entries[i], like: true),
        onSave: () => _engage(entries[i], save: true),
        engaging: _engagingIds.contains(entries[i].id),
        onTap: () {
          final opening = _expandedStoryId != entries[i].id;
          setState(() => _expandedStoryId = opening ? entries[i].id : null);
          if (opening) {
            _engage(entries[i]);
            _engage(entries[i], read: true);
          }
        },
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final bool engaging;
  final bool expanded;

  /// True when this is the user's own journal entry: the like/save/read
  /// community actions are hidden and the author row shows their mood.
  final bool personal;

  const _EntryCard({
    required this.entry,
    required this.onDelete,
    required this.onTap,
    required this.onLike,
    required this.onSave,
    required this.engaging,
    required this.expanded,
    this.personal = false,
  });

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    final meta = _moodMeta(entry.mood, pal);
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: light ? scheme.outlineVariant.withAlpha(100) : pal.stroke,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.image != null && entry.image!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () =>
                        _showJournalMedia(context, entry.image!, entry.title),
                    child: Image.network(
                      api.getMediaUrl(entry.image),
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              height: 170,
                              color: pal.field,
                              alignment: Alignment.center,
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: pal.amber)),
                            ),
                    ),
                  ),
                ),
              if (entry.image != null && entry.image!.isNotEmpty)
                const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.authorName.isEmpty
                              ? 'MURA community'
                              : entry.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(entry.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12.5,
                                height: 1.35)),
                      ],
                    ),
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: meta.color.withValues(alpha: .2),
                      child: Text(meta.emoji,
                          style: const TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        personal
                            ? 'You'
                            : (entry.authorName.isEmpty
                                ? 'MURA community'
                                : entry.authorName),
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(_fmtDateTime(entry.createdAt),
                        style: TextStyle(color: pal.textDim, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(entry.body,
                          style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              height: 1.6)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (!personal) ...[
                    Icon(
                        entry.read
                            ? Icons.done_all_rounded
                            : Icons.menu_book_outlined,
                        size: 16,
                        color: entry.read ? pal.teal : pal.textDim),
                    const SizedBox(width: 5),
                    Text(entry.read ? 'Read' : 'Not read',
                        style:
                            TextStyle(color: pal.textDim, fontSize: 10)),
                    const SizedBox(width: 14),
                    Icon(Icons.visibility_outlined,
                        size: 16, color: pal.textDim),
                    const SizedBox(width: 4),
                    Text('${entry.viewCount}',
                        style: TextStyle(color: pal.textDim, fontSize: 10)),
                    const SizedBox(width: 14),
                  ],
                  if (!personal)
                    IconButton(
                      onPressed: engaging ? null : onLike,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                          entry.liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18,
                          color: entry.liked
                              ? Colors.pinkAccent
                              : pal.textDim),
                      tooltip: entry.liked ? 'Unlike' : 'Like',
                    ),
                  if (!personal)
                    Text('${entry.likeCount}',
                        style: TextStyle(color: pal.textDim, fontSize: 10)),
                  if (!personal)
                    IconButton(
                      onPressed: engaging ? null : onSave,
                      visualDensity: VisualDensity.compact,
                      icon: engaging
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              entry.saved
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              size: 18,
                              color: entry.saved ? pal.amber : pal.textDim,
                            ),
                      tooltip: entry.saved
                          ? 'Remove from saved'
                          : 'Save for later',
                    ),
                  const Spacer(),
                  Text(
                    personal ? _fmtDay(entry.createdAt) : _fmtDateTime(entry.createdAt),
                    style: TextStyle(color: pal.textDim, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showJournalMedia(BuildContext context, String url, String title) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              api.getMediaUrl(url),
              fit: BoxFit.contain,
              semanticLabel: title,
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: MuraPalette.of(context).textDim, size: 32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final MemoryItem memory;

  const _MemoryCard({required this.memory});

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    final hasPhoto = memory.photo != null && memory.photo!.trim().isNotEmpty;
    return Container(
      width: 256,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.stroke),
      ),
      child: hasPhoto
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  api.getMediaUrl(memory.photo),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: pal.field,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_outlined,
                        color: pal.textDim, size: 26),
                  ),
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Container(
                          color: pal.field,
                          alignment: Alignment.center,
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: pal.amber)),
                        ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.45, 1.0],
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 9,
                  right: 9,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(memory.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                      Text(_fmtDay(memory.date),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .65),
                              fontSize: 9.5)),
                    ],
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🏅', style: TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(memory.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: pal.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_fmtDay(memory.date),
                      style: TextStyle(color: pal.textDim, fontSize: 9.5)),
                ],
              ),
            ),
    );
  }
}

class _MoodOpt {
  final String key;
  final String emoji;
  final String label;
  const _MoodOpt(this.key, this.emoji, this.label);
}

class _EntryEditorSheet extends StatefulWidget {
  const _EntryEditorSheet();

  @override
  State<_EntryEditorSheet> createState() => _EntryEditorSheetState();
}

class _EntryEditorSheetState extends State<_EntryEditorSheet> {
  MuraPalette get _pal => MuraPalette.of(context);
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String? _mood;
  bool _saving = false;

  static const List<_MoodOpt> _moods = [
    _MoodOpt('great', '😄', 'Great'),
    _MoodOpt('good', '🙂', 'Good'),
    _MoodOpt('neutral', '😐', 'Neutral'),
    _MoodOpt('low', '😞', 'Low'),
  ];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      _toast(context, 'Give it a title first');
      return;
    }
    setState(() => _saving = true);
    try {
      await api.createJournalEntry(
        title: t,
        body: _body.text.trim(),
        mood: _mood,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Could not save entry');
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _pal.textDim, fontSize: 13.5),
        filled: true,
        fillColor: _pal.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _pal.amber, width: 1.3)),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('New entry',
                    style: TextStyle(
                        color: _pal.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon:
                      Icon(Icons.close_rounded, size: 20, color: _pal.textDim),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _title,
              autofocus: true,
              cursorColor: _pal.amber,
              style: TextStyle(
                  color: _pal.text, fontSize: 15, fontWeight: FontWeight.w600),
              decoration: _deco('Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              cursorColor: _pal.amber,
              minLines: 3,
              maxLines: 6,
              style:
                  TextStyle(color: _pal.text, fontSize: 13.5, height: 1.4),
              decoration: _deco('Write it out…'),
            ),
            const SizedBox(height: 16),
            Text('MOOD',
                style: TextStyle(
                    color: _pal.textDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _moods)
                  ChoiceChip(
                    label: Text('${m.emoji}  ${m.label}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _mood == m.key ? _pal.onAmber : _pal.textDim)),
                    selected: _mood == m.key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _mood = m.key),
                    selectedColor: _pal.amber,
                    backgroundColor: _pal.field,
                    shape:
                        StadiumBorder(side: BorderSide(color: _pal.stroke)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pal.amber,
                  foregroundColor: _pal.onAmber,
                  disabledBackgroundColor: _pal.amber.withValues(alpha: .4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: _saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: _pal.onAmber))
                    : const Text('Save entry',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}