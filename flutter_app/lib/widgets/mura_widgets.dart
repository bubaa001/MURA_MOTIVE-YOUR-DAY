/// Shared MURA widgets — card shell, press feedback, staggered entrances,
/// stat chips. Every page previously copy-pasted its own card decoration;
/// these are the canonical versions (obsidian & amber, theme-aware).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The house card: themed surface, hairline stroke, 18px radius.
class MuraCard extends StatelessWidget {
  const MuraCard({super.key, this.child, this.padding, this.margin});

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final pal = MuraPalette.of(context);
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: pal.stroke),
      ),
      child: child,
    );
  }
}

/// Anything tappable gets a 200ms press scale (0.97) — the same
/// easeOutCubic family the Today checkbox already uses.
class Pressable extends StatefulWidget {
  const Pressable({super.key, this.onTap, this.child});

  final VoidCallback? onTap;
  final Widget? child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1, end: 0.97)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => _ctrl.forward(),
      onTapUp: widget.onTap == null ? null : (_) => _ctrl.reverse(),
      onTapCancel: widget.onTap == null ? null : () => _ctrl.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

/// One-shot staggered entrance: fade + 14px slide over 340ms, delayed by
/// [index] * 60ms. Call `restart()` to replay on refresh.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, this.index = 0, this.child});

  final int index;
  final Widget? child;

  @override
  State<FadeSlideIn> createState() => FadeSlideInState();
}

class FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  void restart() {
    _ctrl.value = 0;
    if (mounted) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(
        opacity: _anim.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _anim.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Animated numeric counter — counts up from 0 to [value] in 700ms.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Linear progress that TWEENS to new values (easeOutCubic, 600ms) —
/// replaces the jumpy `AlwaysStoppedAnimation` bars across Today/Plan.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.trackColor,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final pal = MuraPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: trackColor ?? _pal_field(context),
          valueColor: AlwaysStoppedAnimation<Color>(color ?? pal.amber),
        ),
      ),
    );
  }

  static Color _pal_field(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return isLight
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : const Color(0xFF2A2013);
  }
}

/// Small labelled stat (number over caption) used in rows/grids.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.tint,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final pal = MuraPalette.of(context);
    final color = tint ?? pal.amber;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(height: 7),
        CountUp(
          value: value,
          style: TextStyle(
            color: pal.text,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: pal.textDim,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

/// Loading placeholder: a soft breathing block used while pages fetch, so
/// long lists and stats feel designed while waiting instead of dead space.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = MuraPalette.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Breathe between field and a lighter tone.
        final t = Curves.easeInOut.transform(
            0.5 + 0.5 * (math.sin(_ctrl.value * 2 * math.pi)));
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(pal.field, pal.cardHi, t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}
