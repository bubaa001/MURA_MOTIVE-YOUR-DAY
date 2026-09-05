import 'package:flutter/material.dart';

/// Clean pull-to-refresh widget using Flutter's native [RefreshIndicator].
class WaterDropRefresh extends StatelessWidget {
  const WaterDropRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.threshold = 78,
    this.color = const Color(0xFFFFC174),
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final double threshold;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: color,
      backgroundColor: const Color(0xFF17120D),
      child: child,
    );
  }
}
