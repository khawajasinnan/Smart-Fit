import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:smartfit/shared_widgets/zayn_avatar.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// Floating glass navigation bar.
///
/// Tabs: Home · Try-On · Hair | AI Stylist (Zayn, always in the exact centre)
/// | Saved · Profile. Index == shell branch (app_router.dart): 0 Home, 1 Try-On,
/// 2 Hair, 3 Stylist, 4 Saved, 5 Profile.
class SFBottomNavBar extends StatefulWidget {
  const SFBottomNavBar({super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<SFBottomNavBar> createState() => _SFBottomNavBarState();
}

class _NavItem {
  const _NavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const _items = [
  _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _NavItem(Icons.checkroom_outlined, Icons.checkroom_rounded, 'Try-On'),
  _NavItem(Icons.face_retouching_natural_outlined, Icons.face_retouching_natural, 'Hair'),
  _NavItem(Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Stylist'),
  _NavItem(Icons.favorite_border_rounded, Icons.favorite_rounded, 'Saved'),
  _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
];

/// Zayn's tab (the round centre button).
const int kStylistTab = 3;
const double _centreWidth = 64;

class _SFBottomNavBarState extends State<SFBottomNavBar> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  Widget _tab(int i) => Expanded(
    child: _NavTab(item: _items[i], active: widget.currentIndex == i, onTap: () => _tap(i)),
  );

  void _tap(int index) {
    HapticFeedback.selectionClick();
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, bottomInset > 0 ? bottomInset : AppSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.pillAll,
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 32, offset: const Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              decoration: BoxDecoration(
                color: sf.navFill,
                borderRadius: AppRadius.pillAll,
                border: Border.all(color: sf.navBorder, width: 1.2),
              ),
              // Two equal halves around a fixed centre: Zayn stays exactly in the middle.
              child: Row(
                children: [
                  Expanded(child: Row(children: [for (var i = 0; i < kStylistTab; i++) _tab(i)])),
                  SizedBox(
                    width: _centreWidth,
                    child: _CenterButton(
                      active: widget.currentIndex == kStylistTab,
                      breath: _breath,
                      onTap: () => _tap(kStylistTab),
                    ),
                  ),
                  Expanded(child: Row(children: [for (var i = kStylistTab + 1; i < _items.length; i++) _tab(i)])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.item, required this.active, required this.onTap});

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final color = active ? sf.accentText : sf.textMuted;
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppDurations.base,
                curve: AppCurves.enter,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? (context.isDark
                            ? AppColors.neonLime.withValues(alpha: 0.16)
                            : AppColors.accent600.withValues(alpha: 0.12))
                      : Colors.transparent,
                  borderRadius: AppRadius.pillAll,
                ),
                child: AnimatedScale(
                  scale: active ? 1.08 : 1,
                  duration: AppDurations.base,
                  curve: AppCurves.playful,
                  child: Icon(active ? item.activeIcon : item.icon, size: 22, color: color),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: AppDurations.base,
                style: context.tt.labelSmall!.copyWith(
                  color: color,
                  letterSpacing: 0.2,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(item.label, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.active, required this.breath, required this.onTap});

  final bool active;
  final Animation<double> breath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Semantics(
      selected: active,
      button: true,
      label: 'AI Stylist',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedBuilder(
            animation: breath,
            builder: (context, child) {
              return Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: sf.brandGradient,
                  border: Border.all(color: sf.onBrand.withValues(alpha: active ? 0.9 : 0.35), width: 2),
                  boxShadow: const [],
                ),
                child: child,
              );
            },
            // Zayn, the AI stylist, is the tab's icon
            child: const Padding(padding: EdgeInsets.all(3), child: ZaynAvatar(size: 44)),
          ),
        ),
      ),
    );
  }
}
