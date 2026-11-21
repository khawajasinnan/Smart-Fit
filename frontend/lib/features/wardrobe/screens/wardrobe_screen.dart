import 'dart:convert';
import 'package:smartfit/features/scoring/data/look_score_models.dart';
import 'dart:math' as math;
import 'package:smartfit/features/tryon/screens/tryon_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/utils/store_link.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';
import 'package:smartfit/features/wardrobe/data/models/saved_product.dart';
import 'package:smartfit/features/wardrobe/data/models/wardrobe_category.dart';
import 'package:smartfit/features/wardrobe/providers/wardrobe_provider.dart';
import 'package:smartfit/shared_widgets/clothing_pattern_background.dart';
import 'package:smartfit/shared_widgets/pressable.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';

/// The wardrobe (SFR-035, SFR-036, SFR-037; spec §23.19): saved pieces in a
/// two-column masonry, grouped Today / This week / Earlier, filtered by
/// category chips and sortable. Tap a card to flip it for details and the
/// store link; swipe it left (or use the back of the card) to remove it,
/// with Undo.
class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key});

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

enum _Sort { newest, priceLow, priceHigh }

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  WardrobeCategory? _filter; // null = all
  _Sort _sort = _Sort.newest;

  Future<void> _remove(SavedProduct item) async {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(wardrobeNotifierProvider.notifier);
    await notifier.removeProduct(item.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${item.product.title}'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          action: SnackBarAction(label: 'Undo', onPressed: () => notifier.restore(item)),
        ),
      );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_rounded),
        title: const Text('Clear your wardrobe?'),
        content: const Text('This removes every saved piece. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep them')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(wardrobeNotifierProvider.notifier).clearAll();
  }

  List<SavedProduct> _sorted(List<SavedProduct> items) {
    int price(SavedProduct s) => s.product.pricePkr ?? 0;
    return switch (_sort) {
      _Sort.newest => items,
      _Sort.priceLow => [...items]..sort((a, b) => price(a).compareTo(price(b))),
      _Sort.priceHigh => [...items]..sort((a, b) => price(b).compareTo(price(a))),
    };
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(wardrobeNotifierProvider);
    final counts = <WardrobeCategory, int>{};
    for (final s in all) {
      final c = WardrobeCategory.of(s.product);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final filter = counts.containsKey(_filter) ? _filter : null;
    final visible = [
      for (final s in all)
        if (filter == null || WardrobeCategory.of(s.product) == filter) s,
    ];
    final reduced = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: context.cs.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: ClothingPatternBackground()),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(items: all, onClear: all.isEmpty ? null : _confirmClear),
                ),
                if (all.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyWardrobe())
                else ...[
                  SliverToBoxAdapter(
                    child: _Filters(
                      counts: counts,
                      total: all.length,
                      selected: filter,
                      sort: _sort,
                      onSelect: (c) => setState(() => _filter = c),
                      onSort: (s) => setState(() => _sort = s),
                    ),
                  ),
                  if (_sort == _Sort.newest)
                    for (final entry in groupByRecency(visible, DateTime.now()).entries) ...[
                      SliverToBoxAdapter(
                        child: _SectionTitle(label: entry.key.label, count: entry.value.length),
                      ),
                      SliverToBoxAdapter(
                        child: _Masonry(items: entry.value, onRemove: _remove, animate: !reduced),
                      ),
                    ]
                  else
                    SliverToBoxAdapter(
                      child: _Masonry(items: _sorted(visible), onRemove: _remove, animate: !reduced),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 130)), // above the nav bar
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header with live stats ───────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.items, required this.onClear});

  final List<SavedProduct> items;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final brands = {for (final s in items) s.product.brand.toLowerCase()}.length;
    final worth = items.fold<int>(0, (sum, s) => sum + (s.product.pricePkr ?? 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Wardrobe', style: context.tt.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      'Everything you saved, ready to wear',
                      style: context.tt.bodyMedium?.copyWith(color: context.sf.textMuted),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear wardrobe',
                  onPressed: onClear,
                  icon: Icon(Icons.delete_sweep_rounded, color: context.cs.error),
                ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(value: items.length, label: 'Pieces', icon: Icons.checkroom_rounded),
                const SizedBox(width: 10),
                _Stat(value: brands, label: 'Brands', icon: Icons.storefront_rounded),
                const SizedBox(width: 10),
                _Stat(value: worth, label: 'Worth', icon: Icons.payments_rounded, compact: true, prefix: 'Rs '),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon, this.compact = false, this.prefix = ''});

  final int value;
  final String label;
  final IconData icon;
  final String prefix;

  /// 12500 -> "12.5k"
  final bool compact;

  static String _format(int v, bool compact) {
    if (!compact || v < 1000) return '$v';
    final k = v / 1000;
    return '${k >= 100 ? k.round() : k.toStringAsFixed(1).replaceAll('.0', '')}k';
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.sf.glassFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.sf.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: context.sf.brandGradient),
              child: Icon(icon, size: 14, color: context.sf.onBrand),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value.toDouble()),
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$prefix${_format(v.round(), compact)}',
                        style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.labelSmall?.copyWith(color: context.sf.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Category chips + sort ────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  const _Filters({
    required this.counts,
    required this.total,
    required this.selected,
    required this.sort,
    required this.onSelect,
    required this.onSort,
  });

  final Map<WardrobeCategory, int> counts;
  final int total;
  final WardrobeCategory? selected;
  final _Sort sort;
  final ValueChanged<WardrobeCategory?> onSelect;
  final ValueChanged<_Sort> onSort;

  @override
  Widget build(BuildContext context) {
    final cats = [
      for (final c in WardrobeCategory.values)
        if (counts.containsKey(c)) c,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _Chip(
                    label: 'All',
                    count: total,
                    icon: Icons.apps_rounded,
                    selected: selected == null,
                    onTap: () => onSelect(null),
                  ),
                  for (final c in cats)
                    _Chip(
                      label: c.label,
                      count: counts[c]!,
                      icon: c.icon,
                      selected: selected == c,
                      onTap: () => onSelect(c),
                    ),
                ],
              ),
            ),
          ),
          PopupMenuButton<_Sort>(
            tooltip: 'Sort',
            initialValue: sort,
            onSelected: onSort,
            icon: Icon(Icons.swap_vert_rounded, color: context.cs.primary),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.newest, child: Text('Newest first')),
              PopupMenuItem(value: _Sort.priceLow, child: Text('Price: low to high')),
              PopupMenuItem(value: _Sort.priceHigh, child: Text('Price: high to low')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.sf.onBrand : context.cs.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count',
        excludeSemantics: true,
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: selected ? context.sf.brandGradient : null,
              color: selected ? null : context.sf.glassFill,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: selected ? Colors.transparent : context.sf.glassBorder),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: context.tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? context.sf.onBrand.withValues(alpha: 0.12) : context.cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: context.tt.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [context.sf.highlight, AppColors.accent600],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(label, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text('$count', style: context.tt.titleSmall?.copyWith(color: context.sf.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ── Masonry ──────────────────────────────────────────────────────────────────

/// Two columns; each card goes to the shorter column. Card shapes vary
/// (tall / square / short) so the grid looks hand-styled, and a product
/// always keeps the same shape.
class _Masonry extends StatelessWidget {
  const _Masonry({required this.items, required this.onRemove, required this.animate});

  final List<SavedProduct> items;
  final ValueChanged<SavedProduct> onRemove;
  final bool animate;

  static const _shapes = [0.72, 0.9, 0.64, 0.82, 1.0];

  static double shapeOf(String key) =>
      _shapes[key.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff) % _shapes.length];

  @override
  Widget build(BuildContext context) {
    if (items.length == 1) {
      // one piece: a wide "featured" card instead of half an empty row
      final item = items.single;
      Widget card = _SwipeToRemove(
        item: item,
        onRemove: onRemove,
        child: _FlipCard(item: item, aspect: 1.55, onRemove: () => onRemove(item)),
      );
      if (animate) card = card.animate().fadeIn(duration: 380.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic);
      return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: card);
    }
    final left = <Widget>[], right = <Widget>[];
    var hl = 0.0, hr = 0.0;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final shape = shapeOf(item.key);
      Widget card = Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _SwipeToRemove(
          item: item,
          onRemove: onRemove,
          child: _FlipCard(item: item, aspect: shape, onRemove: () => onRemove(item)),
        ),
      );
      if (animate) {
        card = card
            .animate(delay: (60 * math.min(i, 10)).ms)
            .fadeIn(duration: 380.ms)
            .slideY(begin: 0.12, curve: Curves.easeOutCubic)
            .scale(begin: const Offset(0.96, 0.96), curve: Curves.easeOutCubic);
      }
      final h = 1 / shape + 0.42; // image height + text, in card widths
      if (hl <= hr) {
        left.add(card);
        hl += h;
      } else {
        right.add(card);
        hr += h;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: 14),
          Expanded(child: Column(children: right)),
        ],
      ),
    );
  }
}

class _SwipeToRemove extends StatelessWidget {
  const _SwipeToRemove({required this.item, required this.onRemove, required this.child});

  final SavedProduct item;
  final ValueChanged<SavedProduct> onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('wardrobe-${item.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(color: context.cs.error, borderRadius: BorderRadius.circular(24)),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white),
            SizedBox(height: 4),
            Text(
              'Remove',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Tap to flip: the photo on the front, details and actions on the back.
class _FlipCard extends StatefulWidget {
  const _FlipCard({required this.item, required this.aspect, required this.onRemove});

  final SavedProduct item;
  final double aspect;
  final VoidCallback onRemove;

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _flip.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    _showBack = !_showBack;
    if (MediaQuery.of(context).disableAnimations) {
      _flip.value = _showBack ? 1 : 0;
    } else {
      _showBack ? _flip.forward() : _flip.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeInOutCubic.transform(_flip.value);
    final angle = t * math.pi;
    final front = t < 0.5;
    final p = widget.item.product;
    return Semantics(
      button: true,
      label:
          '${p.title} by ${p.brand}${p.pricePkr != null ? ', PKR ${p.pricePkr}' : ''}. '
          '${_showBack ? 'Showing details. Tap to see the photo' : 'Tap for details'}',
      child: Pressable(
        onTap: _toggle,
        pressedScale: 0.97,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          // The front always sets the size; the back covers it exactly.
          child: Stack(
            children: [
              Opacity(
                opacity: front ? 1 : 0,
                child: _CardFront(item: widget.item, aspect: widget.aspect),
              ),
              if (!front)
                Positioned.fill(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _CardBack(item: widget.item, onRemove: widget.onRemove),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.sf.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.sf.glassBorder),
        boxShadow: [
          BoxShadow(color: Color(0x0F000000), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

String _price(ProductRecommendation p) {
  final v = p.pricePkr;
  if (v == null) return '';
  final s = v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return 'PKR $s';
}

class _CardFront extends StatelessWidget {
  const _CardFront({required this.item, required this.aspect});

  final SavedProduct item;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (p.imageUrl != null && p.imageUrl!.isNotEmpty)
                  SafeNetworkImage(imageUrl: p.imageUrl!, fit: BoxFit.cover)
                else
                  Container(
                    color: context.cs.surfaceContainerHigh,
                    child: Icon(Icons.checkroom_rounded, size: 40, color: context.cs.outlineVariant),
                  ),
                // soft fade so the price chip reads on any photo
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.6, 1],
                      colors: [Colors.transparent, Color(0x66000000)],
                    ),
                  ),
                ),
                if (_price(p).isNotEmpty)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _price(p),
                        style: const TextStyle(color: Color(0xFF1E1638), fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                  ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                    child: const Icon(Icons.favorite_rounded, size: 14, color: AppColors.hotPink),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.brand.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelSmall?.copyWith(
                    color: context.sf.accentText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _savedAgo(DateTime savedAt) {
  if (savedAt.millisecondsSinceEpoch == 0) return 'Saved a while ago';
  final d = DateTime.now().difference(savedAt);
  if (d.inMinutes < 1) return 'Saved just now';
  if (d.inHours < 1) return 'Saved ${d.inMinutes} min ago';
  if (d.inDays < 1) return 'Saved ${d.inHours} h ago';
  if (d.inDays == 1) return 'Saved yesterday';
  return 'Saved ${d.inDays} days ago';
}

/// The hairstyle saved with a wardrobe item (SFR-035/036): its picture and name.
class _SavedHairstyle extends StatelessWidget {
  const _SavedHairstyle({required this.hair});

  final ChosenHairstyle hair;

  @override
  Widget build(BuildContext context) {
    final thumb = hair.thumbBase64;
    Uint8List? bytes;
    if (thumb != null) {
      try {
        bytes = base64Decode(thumb);
      } catch (_) {
        bytes = null;
      }
    }
    return Semantics(
      label: 'Hairstyle: ${hair.name}',
      excludeSemantics: true,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 28,
              height: 34,
              child: bytes == null
                  ? ColoredBox(
                      color: context.cs.surfaceContainerHigh,
                      child: Icon(Icons.face_retouching_natural, size: 16, color: context.cs.primary),
                    )
                  : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Hair: ${hair.name}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardBack extends ConsumerWidget {
  const _CardBack({required this.item, required this.onRemove});

  final SavedProduct item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = item.product;
    final sizes = p.sizes.take(6).join(' · ');
    return _CardShell(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [context.sf.highlight.withValues(alpha: context.isDark ? 0.07 : 0.10), AppColors.accent600.withValues(alpha: 0.08)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // details clip on very short cards; the actions always fit
              Expanded(
                child: ClipRect(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(WardrobeCategory.of(p).icon, size: 16, color: context.cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              WardrobeCategory.of(p).label,
                              style: context.tt.labelMedium?.copyWith(
                                color: context.cs.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${p.brand}${_price(p).isNotEmpty ? ' · ${_price(p)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted),
                      ),
                      if (p.recommendedSize != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Your size: ${p.recommendedSize}',
                          style: context.tt.labelMedium?.copyWith(
                            color: context.sf.accentText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ] else if (sizes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(sizes, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelSmall),
                      ],
                      if (ChosenHairstyle.fromWardrobeJson(p.hairstyle) case final hair?) ...[
                        const SizedBox(height: 8),
                        _SavedHairstyle(hair: hair), // SFR-036
                      ],
                    ],
                  ),
                ),
              ),
              Text(_savedAgo(item.savedAt), style: context.tt.labelSmall?.copyWith(color: context.sf.textMuted)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => openStoreLink(context, p.productUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const FittedBox(child: Text('View on store')),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              // SFR-035: a saved try-on opens as the 360° view; otherwise try it on now.
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => p.hasTryOn ? showSavedTryOn(context, ref, p) : openTryOn(context, ref, p),
                  icon: const Icon(Icons.threesixty_rounded, size: 16),
                  label: FittedBox(child: Text(p.hasTryOn ? 'My try-on' : 'Try on')),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline_rounded, size: 16, color: context.cs.error),
                  label: FittedBox(
                    child: Text('Remove', style: TextStyle(color: context.cs.error)),
                  ),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty ────────────────────────────────────────────────────────────────────

class _EmptyWardrobe extends StatelessWidget {
  const _EmptyWardrobe();

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    Widget zayn = Image.asset(
      'assets/mascot/still/shrug.png',
      width: 170,
      height: 170,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const SizedBox(height: 170),
    );
    if (!reduced) {
      zayn = zayn
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(begin: -4, end: 6, duration: 1800.ms, curve: Curves.easeInOut);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 140),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          zayn,
          const SizedBox(height: 12),
          Text(
            'Your wardrobe is empty',
            textAlign: TextAlign.center,
            style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            "Zayn says: \"Empty closet? Not on my watch.\" Save the looks you love from the AI Stylist and they'll live here.",
            textAlign: TextAlign.center,
            style: context.tt.bodyMedium?.copyWith(color: context.sf.textMuted),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => context.go(RoutePaths.chat),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Find looks with Zayn'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          ),
        ],
      ),
    );
  }
}
