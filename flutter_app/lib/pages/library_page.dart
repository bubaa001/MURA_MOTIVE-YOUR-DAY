/// MURA — Library page: daily rotation + browsable quotes/prayers/philosophy.
///
/// Assumes the shared api singleton from ../api.dart exposes:
///   dailyContent() -> DailyContent   // {date, quote, prayer, philosophy}
///   contentItems({String? type}) -> List`<ContentItem`>
/// And ../models.dart types:
///   ContentItem {id, type, text, source, tags}
///   DailyContent {quote, prayer, philosophy}   // ContentItem? each
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../refresh_bus.dart';
import '../models.dart';
import '../theme.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with AppRefreshListener {
  MuraPalette get _pal => MuraPalette.of(context);
  DailyContent? _daily;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadDaily();
  }

  @override
  void onAppRefresh() => _loadDaily();

  Future<void> _loadDaily() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await api.dailyContent();
      if (!mounted) return;
      setState(() {
        _daily = d;
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (_busy && _daily == null) {
      body = Center(child: CircularProgressIndicator(color: _pal.amber));
    } else if (_err != null && _daily == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: _pal.textDim, size: 36),
            const SizedBox(height: 12),
            Text('Something broke: ${_err!}',
                textAlign: TextAlign.center,
                style: TextStyle(color: _pal.textDim, fontSize: 12.5)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _loadDaily,
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _pal.amber)),
              child: Text('Retry', style: TextStyle(color: _pal.amber)),
            ),
          ],
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(splashFactory: NoSplash.splashFactory),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: scheme.primary.withAlpha(28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  labelStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Quotes'),
                    Tab(text: 'Insight'),
                    Tab(text: 'Philosophy'),
                    Tab(text: 'Saved'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LibraryTab(
                  type: 'quote',
                  plural: 'quotes',
                  dailyLabel: "TODAY'S QUOTE",
                  accent: _pal.amber,
                  daily: _daily?.quote,
                ),
                _LibraryTab(
                  type: 'spiritual_insight',
                  plural: 'insights',
                  dailyLabel: "TODAY'S INSIGHT",
                  accent: _pal.teal,
                  daily: _daily?.insight,
                ),
                _LibraryTab(
                  type: 'philosophy',
                  plural: 'philosophies',
                  dailyLabel: "TODAY'S PHILOSOPHY",
                  accent: const Color(0xFFC7C8FF),
                  daily: _daily?.philosophy,
                ),
                _LibraryTab(
                  type: null,
                  plural: 'saved items',
                  dailyLabel: '',
                  accent: _pal.amber,
                  daily: null,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(bottom: false, child: body),
      ),
    );
  }
}

class _LibraryTab extends StatefulWidget {
  final String? type;
  final String plural;
  final String dailyLabel;
  final Color accent;
  final ContentItem? daily;

  const _LibraryTab({
    required this.type,
    required this.plural,
    required this.dailyLabel,
    required this.accent,
    required this.daily,
  });

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab>
    with AutomaticKeepAliveClientMixin, AppRefreshListener {
  MuraPalette get _pal => MuraPalette.of(context);
  List<ContentItem>? _items;
  bool _busy = false;
  String? _err;
  
  // 🔑 Track which item is expanded
  int? _expandedItemId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onAppRefresh() => _load();

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final items = await api.contentItems(
          type: widget.type,
          status: widget.type == null ? 'saved' : null,
          pageSize: 200);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_busy && _items == null) {
      return Center(child: CircularProgressIndicator(color: _pal.amber));
    }
    return RefreshIndicator(
      color: widget.accent,
      backgroundColor: _pal.card,
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final items = _items ?? const [];
    final children = <Widget>[];

    if (_err != null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, color: _pal.textDim, size: 32),
            const SizedBox(height: 10),
            Text('Could not load ${widget.plural}: ${_err!}',
                textAlign: TextAlign.center,
                style: TextStyle(color: _pal.textDim, fontSize: 12)),
          ],
        ),
      ));
    }

    if (widget.daily != null) {
      children.add(_HeroCard(
          item: widget.daily!,
          accent: widget.accent,
          label: widget.dailyLabel));
      children.add(const SizedBox(height: 18));
    }

    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        children: [
          Text('${widget.plural.toUpperCase()} LIBRARY',
              style: TextStyle(
                  color: _pal.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
          const Spacer(),
          Text('${items.length}',
              style: TextStyle(
                  color: widget.accent.withValues(alpha: .8), fontSize: 11)),
        ],
      ),
    ));

    if (items.isEmpty && _err == null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.auto_stories_rounded,
                color: _pal.textDim.withValues(alpha: .6), size: 34),
            const SizedBox(height: 10),
            Text('Nothing here yet',
                style: TextStyle(color: _pal.textDim, fontSize: 12.5)),
          ],
        ),
      ));
    }

    for (final item in items) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _QuoteCard(
          item: item,
          accent: widget.accent,
          expanded: _expandedItemId == item.id,
          onTap: () {
            setState(() {
              _expandedItemId = _expandedItemId == item.id ? null : item.id;
            });
          },
          onSave: (updated) {
            final index =
                _items?.indexWhere((candidate) => candidate.id == updated.id) ??
                    -1;
            if (index < 0 || !mounted) return;
            setState(() {
              if (updated.saved || widget.type != null) {
                _items![index] = updated;
              } else {
                _items!.removeAt(index);
              }
            });
          },
        ),
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }
}

// Shared serif text style -- no font assets required, uses the platform's
// generic serif family which reads elegantly against the dark surfaces.
const TextStyle _serif = TextStyle(fontFamily: 'serif');

String _withQuotes(String text) => '"${text.replaceAll('"', "'")}"';

IconData widgetIcon(String type) {
  switch (type) {
    case 'spiritual_insight':
      return Icons.auto_awesome_outlined;
    case 'philosophy':
      return Icons.psychology_outlined;
    default:
      return Icons.wb_twilight_outlined;
  }
}

String widgetLabel(String type) {
  switch (type) {
    case 'spiritual_insight':
      return 'SPIRITUAL INSIGHT';
    case 'philosophy':
      return 'PHILOSOPHY';
    default:
      return 'MORNING RITUAL';
  }
}

class _HeroCard extends StatelessWidget {
  final ContentItem item;
  final Color accent;
  final String label;

  const _HeroCard(
      {required this.item, required this.accent, required this.label});

  @override
  Widget build(BuildContext context) {
    final MuraPalette pal = MuraPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [accent.withValues(alpha: .12), scheme.surfaceContainer]
              : [accent.withValues(alpha: .16), pal.card],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: light
                ? scheme.outlineVariant.withAlpha(100)
                : accent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .18),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Icons.auto_awesome_rounded, size: 21, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(_withQuotes(item.text),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: _serif.copyWith(
                  color: scheme.onSurface,
                  fontSize: 17,
                  height: 1.45,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                  width: 22, height: 1, color: accent.withValues(alpha: .6)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  (item.source.trim().isEmpty) ? 'Unknown source' : item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _serif.copyWith(
                      color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final ContentItem item;
  final Color accent;
  final bool expanded;
  final VoidCallback onTap;
  final ValueChanged<ContentItem> onSave;

  const _QuoteCard({
    required this.item,
    required this.accent,
    required this.expanded,
    required this.onTap,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final MuraPalette pal = MuraPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;

    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: light ? scheme.outlineVariant.withAlpha(100) : pal.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.image != null && item.image!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () =>
                        _showMedia(context, item.image!, widgetLabel(item.type)),
                    child: Image.network(
                      api.getMediaUrl(item.image),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              height: 150,
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
                const SizedBox(height: 14),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widgetIcon(item.type),
                      color: accent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widgetLabel(item.type),
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _withQuotes(item.text),
                          maxLines: expanded ? null : 5,
                          overflow: expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Show full content when expanded
              if (expanded) ...[
                const SizedBox(height: 14),
                // Full source info
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 1,
                      color: accent.withValues(alpha: .6),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        (item.source.trim().isEmpty)
                            ? 'Unknown source'
                            : item.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _serif.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: item.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('#$tag',
                            style: TextStyle(
                                color: accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700)),
                      );
                    }).toList(),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  // Show source in compact form when collapsed
                  if (!expanded)
                    Expanded(
                      child: Text(
                        (item.source.trim().isEmpty) ? '' : '- ${item.source}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _serif.copyWith(
                            color: accent.withValues(alpha: .75),
                            fontSize: 12,
                            fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    const Spacer(),
                  // Expand/collapse indicator
                  IconButton(
                    onPressed: onTap,
                    icon: Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    tooltip: expanded ? 'Collapse' : 'Expand',
                  ),
                  IconButton(
                    onPressed: () async {
                      try {
                        onSave(await api.saveContent(item.id));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Could not save this item.')),
                          );
                        }
                      }
                    },
                    tooltip: item.saved ? 'Remove from saved' : 'Save for later',
                    icon: Icon(
                      item.saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: item.saved ? accent : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (!expanded && item.tags.isNotEmpty)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('#${item.tags.first}',
                          style: TextStyle(
                              color: accent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMedia(BuildContext context, String url, String title) {
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