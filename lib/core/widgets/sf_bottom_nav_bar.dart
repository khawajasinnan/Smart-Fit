import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/sf_transition_loader.dart';

/// SmartFit Ultra-Aesthetic Gen-Z Glassmorphic Bottom Navigation Bar.
///
/// Features:
///  - High-refraction double-layer glassmorphism with heavy blur
///  - Iridescent gradient border (Hot Pink → Neon Violet → Frost)
///  - Smooth spring tap-scale animations on each tab when clicked
///  - Floating center AI Stylist button with breathing aura and tactile haptics
///  - Active selection glowing gradient capsule with indicator micro-gem
class SFBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const SFBottomNavBar({
    super.key,
    required this.currentIndex,
    this.onTap,
  });

  @override
  State<SFBottomNavBar> createState() => _SFBottomNavBarState();
}

class _SFBottomNavBarState extends State<SFBottomNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _defaultNavigate(BuildContext context, int index) {
    if (index == widget.currentIndex) return;
    switch (index) {
      case 0:
        SFNavHelper.navigateWithLoader(
          context,
          RoutePaths.home,
          title: 'Home Dashboard',
          subtitle: 'Loading your style feed...',
          replace: true,
        );
        break;
      case 1:
        SFNavHelper.navigateWithLoader(
          context,
          RoutePaths.wardrobe,
          title: 'Digital Wardrobe',
          subtitle: 'Syncing your saved fits & closet...',
        );
        break;
      case 2:
        SFNavHelper.navigateWithLoader(
          context,
          RoutePaths.chat,
          title: 'AI Stylist Chat',
          subtitle: 'Connecting with your personal stylist...',
        );
        break;
      case 3:
        SFNavHelper.navigateWithLoader(
          context,
          RoutePaths.tryOn,
          title: 'Virtual Try-On',
          subtitle: 'Calibrating 3D fitting canvas...',
        );
        break;
      case 4:
        SFNavHelper.navigateWithLoader(
          context,
          RoutePaths.settings,
          title: 'Settings & Profile',
          subtitle: 'Loading account preferences...',
        );
        break;
    }
  }

  void _handleTap(int index) {
    HapticFeedback.lightImpact();
    if (widget.onTap != null) {
      widget.onTap!(index);
    } else {
      _defaultNavigate(context, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad > 0 ? bottomPad : 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(42),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: Container(
            height: 78,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(42),
              border: Border.all(
                color: const Color(0xFFFF2E93).withValues(alpha: 0.22),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF2E93).withValues(alpha: 0.12),
                  blurRadius: 36,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: const Color(0xFF6C4CE0).withValues(alpha: 0.08),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _InteractiveNavTab(
                  index: 0,
                  currentIndex: widget.currentIndex,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () => _handleTap(0),
                ),
                _InteractiveNavTab(
                  index: 1,
                  currentIndex: widget.currentIndex,
                  icon: Icons.checkroom_outlined,
                  activeIcon: Icons.checkroom_rounded,
                  label: 'Wardrobe',
                  onTap: () => _handleTap(1),
                ),
                _InteractiveCenterTab(
                  isActive: widget.currentIndex == 2,
                  pulseAnimation: _pulseCtrl,
                  onTap: () => _handleTap(2),
                ),
                _InteractiveNavTab(
                  index: 3,
                  currentIndex: widget.currentIndex,
                  icon: Icons.face_retouching_natural_outlined,
                  activeIcon: Icons.face_retouching_natural,
                  label: 'Try-On',
                  onTap: () => _handleTap(3),
                ),
                _InteractiveNavTab(
                  index: 4,
                  currentIndex: widget.currentIndex,
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Profile',
                  onTap: () => _handleTap(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An interactive navigation tab that animates on tap with a bouncy spring scale effect
class _InteractiveNavTab extends StatefulWidget {
  final int index;
  final int currentIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  const _InteractiveNavTab({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_InteractiveNavTab> createState() => _InteractiveNavTabState();
}

class _InteractiveNavTabState extends State<_InteractiveNavTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapCtrl;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.84).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _tapCtrl.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _tapCtrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _tapCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.currentIndex == widget.index;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: SizedBox(
          width: 58,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                width: isActive ? 44 : 38,
                height: isActive ? 40 : 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [
                            Color(0xFFFF2E93),
                            Color(0xFF8A2BE2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF2E93).withValues(alpha: 0.38),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: const Color(0xFF6C4CE0).withValues(alpha: 0.22),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Icon(
                    isActive ? widget.activeIcon : widget.icon,
                    size: isActive ? 22 : 21,
                    color: isActive
                        ? Colors.white
                        : AppColors.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 240),
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.3,
                  color: isActive
                      ? const Color(0xFFFF2E93)
                      : AppColors.onSurfaceVariant.withValues(alpha: 0.68),
                ),
                child: Text(widget.label, maxLines: 1),
              ),
              const SizedBox(height: 2),
              // Glowing micro gem dot for active tab
              AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: isActive ? 1.0 : 0.0,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFF2E93),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFFF2E93),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated Center AI Stylist Floating Action Tab
class _InteractiveCenterTab extends StatefulWidget {
  final bool isActive;
  final Animation<double> pulseAnimation;
  final VoidCallback onTap;

  const _InteractiveCenterTab({
    required this.isActive,
    required this.pulseAnimation,
    required this.onTap,
  });

  @override
  State<_InteractiveCenterTab> createState() => _InteractiveCenterTabState();
}

class _InteractiveCenterTabState extends State<_InteractiveCenterTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapCtrl;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _tapCtrl.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _tapCtrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _tapCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: widget.pulseAnimation,
                builder: (context, child) {
                  final glow = 0.28 + (widget.pulseAnimation.value * 0.28);
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2E93).withValues(alpha: glow),
                          blurRadius: 24,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: const Color(0xFF6C4CE0).withValues(alpha: glow * 0.85),
                          blurRadius: 28,
                          spreadRadius: 1,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  width: widget.isActive ? 54 : 50,
                  height: widget.isActive ? 54 : 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF2E93),
                        Color(0xFF8A2BE2),
                        Color(0xFF6C4CE0),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.8),
                      width: 2.2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      widget.isActive ? Icons.auto_awesome : Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: widget.isActive ? 27 : 25,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 240),
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: widget.isActive ? FontWeight.w800 : FontWeight.w700,
                  letterSpacing: 0.3,
                  color: widget.isActive
                      ? const Color(0xFFFF2E93)
                      : const Color(0xFF6C4CE0),
                ),
                child: const Text('AI Stylist', maxLines: 1),
              ),
              const SizedBox(height: 2),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: widget.isActive ? 1.0 : 0.0,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6C4CE0),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF6C4CE0),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
