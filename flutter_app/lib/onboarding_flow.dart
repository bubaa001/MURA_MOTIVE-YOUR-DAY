import 'package:flutter/material.dart';

import 'api.dart';

/// MURA onboarding: a five-beat animated sequence in the Obsidian & Amber
/// language.
///
/// 1. Splash   - headline + glowing amber orb rising from the bottom edge;
///               swipe up to enter.
/// 2. Reveal   - the orb stretches upward elastically, bubbles teasing the
///               app's contents float up, and it resolves into the flame
///               mark. Auth buttons fade in beneath (beats 2 + 3 share a
///               screen so the moment stays continuous).
/// 3. Choice   - Apple / Google pills + email link (part of the reveal).
/// 4. Log in   - 'Welcome back.' frosted-glass fields.
/// 5. Register - 'Start building.' frosted-glass fields.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    this.authEnabled = true,
    this.onFinished,
  });

  /// When false the flow is a pure session intro: the reveal plays without
  /// auth buttons and [onFinished] fires once it settles.
  final bool authEnabled;

  /// Called when the flow is done and the app should take over.
  final VoidCallback? onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Stage { login, register }

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Stage _stage = _Stage.login;

  void _enterApp() {
    widget.onFinished?.call();
    if (Navigator.of(context).canPop()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  void _goto(_Stage stage) {
    if (!mounted) return;
    setState(() => _stage = stage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131313),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (Widget child, Animation<double> a) {
          return FadeTransition(
            opacity: a,
            child: child,
          );
        },
        child: switch (_stage) {
          _Stage.login => _AuthForm(
              key: const ValueKey<_Stage>(_Stage.login),
              isRegister: false,
              onDone: _enterApp,
              onSwitch: () => _goto(_Stage.register),
            ),
          _Stage.register => _AuthForm(
              key: const ValueKey<_Stage>(_Stage.register),
              isRegister: true,
              onDone: _enterApp,
              onSwitch: () => _goto(_Stage.login),
            ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sequence 1 - splash with the rising orb
// ---------------------------------------------------------------------------
class _SplashScreen extends StatefulWidget {
  const _SplashScreen({required this.onSwipeUp});

  final VoidCallback onSwipeUp;

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _fade.dispose();
    _shimmer.dispose();
    _breathe.dispose();
    super.dispose();
  }

  void _onDrag(DragEndDetails d) {
    if (d.velocity.pixelsPerSecond.dy < -320) widget.onSwipeUp();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSwipeUp,
      onVerticalDragEnd: _onDrag,
      onVerticalDragUpdate: (DragUpdateDetails d) {
        if (d.delta.dy < -7) widget.onSwipeUp();
      },
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
              child: Column(
                children: <Widget>[
                  const Spacer(flex: 5),
                  const Text(
                    'A new era of discipline is here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE5E2E1),
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.25,
                    ),
                  ),
                  const Spacer(flex: 6),
                  // swipe hint
                  Column(
                    children: <Widget>[
                      Icon(Icons.keyboard_arrow_up_rounded,
                          color:
                              const Color(0xFFFFC174).withValues(alpha: 0.85),
                          size: 30),
                      const SizedBox(height: 2),
                      Text(
                        'Swipe up to enter',
                        style: TextStyle(
                          color: const Color(0xFFA79B8A).withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 46),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // The rising orb, half cut by the bottom edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: -110,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _fade,
                curve: const Interval(0.25, 1, curve: Curves.easeOut),
              ),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.03)
                    .animate(CurvedAnimation(
                  parent: _breathe,
                  curve: Curves.easeInOut,
                )),
                child: _Orb(size: 300, shimmer: _shimmer),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The orb itself: amber glass ball with a slowly rotating shimmer.
// ---------------------------------------------------------------------------
class _Orb extends StatelessWidget {
  const _Orb({this.size = 300, required this.shimmer});

  final double size;
  final Animation<double> shimmer;

  @override
  Widget build(BuildContext context) {
    final Animation<double> spin = shimmer;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // core glow
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.25, -0.35),
                  radius: 0.95,
                  colors: <Color>[
                    Color(0xFFFFE3B3),
                    Color(0xFFFFC174),
                    Color(0xFFB97A1F),
                    Color(0xFF3D2A08),
                  ],
                  stops: <double>[0.05, 0.35, 0.7, 1],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFFC174).withValues(alpha: 0.3),
                    blurRadius: 44,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            // rotating shimmer sweep
            ClipOval(
              child: AnimatedBuilder(
                animation: spin,
                builder: (BuildContext context, Widget? _) {
                  return Transform.rotate(
                    angle: spin.value * 2 * 3.141592653589793,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: SweepGradient(
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const <double>[0.32, 0.5, 0.68],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sequences 2 + 3 - elastic rise, teaser bubbles, flame resolve, auth choice
// ---------------------------------------------------------------------------
class _RevealScreen extends StatefulWidget {
  const _RevealScreen({
    required this.onEmail,
    required this.onApple,
    required this.onGoogle,
  })  : authEnabled = true,
        onSettled = null;

  final VoidCallback onEmail;
  final VoidCallback onApple;
  final VoidCallback onGoogle;

  /// False for the signed-in session intro: no auth buttons; [onSettled]
  /// fires shortly after the animation completes.
  final bool authEnabled;
  final VoidCallback? onSettled;

  @override
  State<_RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends State<_RevealScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  late final AnimationController _buttons = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.authEnabled) {
      _buttons.forward();
    }
    _fx.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) {
        if (!widget.authEnabled) {
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            if (mounted) widget.onSettled?.call();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _fx.dispose();
    _buttons.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double h = c.maxHeight;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // rising teaser bubbles
              ..._bubbles(h),
              // the orb, rising and resolving into the flame mark
              AnimatedBuilder(
                animation: _fx,
                builder: (BuildContext context, Widget? _) {
                  final double t = _fx.value;
                  final double rise =
                      Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
                  final double stretchProgress =
                      ((t - 0.15) / 0.45).clamp(0.0, 1.0);
                  final double stretch =
                      Curves.easeOutCubic.transform(stretchProgress);
                  final double stretchFactor = 4 * stretch * (1 - stretch);
                  final double resolve = Curves.easeInOutCubic
                      .transform(((t - 0.55) / 0.45).clamp(0.0, 1.0));
                  final double orbSize =
                      (300 - 240 * resolve).clamp(60.0, 300.0);
                  final double markOpacity =
                      ((resolve - 0.4) / 0.6).clamp(0.0, 1.0);

                  return Positioned(
                    bottom: -110 + (h * 0.42) * rise + 60 * resolve,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translateByDouble(0, -10 * stretchFactor, 0, 1)
                        ..scaleByDouble(1 - 0.04 * stretchFactor,
                            1 + 0.08 * stretchFactor, 1, 1),
                      child: Opacity(
                        opacity: (1 - 0.1 * resolve).clamp(0.0, 1.0),
                        child: SizedBox(
                          width: orbSize,
                          height: orbSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              Opacity(
                                opacity: (1.0 - markOpacity).clamp(0.0, 1.0),
                                child: _Orb(
                                  size: orbSize,
                                  shimmer: _fx,
                                ),
                              ),
                              Opacity(
                                opacity: markOpacity,
                                child: _FlameMark(size: orbSize),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // headline
              Positioned(
                top: h * 0.16,
                left: 32,
                right: 32,
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _fx,
                    curve: const Interval(0.72, 0.95, curve: Curves.easeOut),
                  ),
                  child: const Column(
                    children: <Widget>[
                      Text(
                        'Meet MURA.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFFC174),
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Build with discipline.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFE5E2E1),
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // auth choice buttons (skipped during a signed-in session intro)
              if (widget.authEnabled)
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 34,
                  child: FadeTransition(
                    opacity: _buttons,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _buttons,
                        curve: Curves.easeOutCubic,
                      )),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _SocialPill(
                            label: 'Continue with Apple',
                            background: const Color(0xFF0A0A0A),
                            foreground: const Color(0xFFE5E2E1),
                            border: const Color(0xFF3A3A3A),
                            icon: Icons.apple_rounded,
                            onTap: widget.onApple,
                          ),
                          const SizedBox(height: 12),
                          _SocialPill(
                            label: 'Continue with Google',
                            background: const Color(0xFFF3EEE6),
                            foreground: const Color(0xFF2A2015),
                            border: Colors.transparent,
                            icon: Icons.g_mobiledata_rounded,
                            onTap: widget.onGoogle,
                          ),
                          const SizedBox(height: 18),
                          TextButton(
                            onPressed: widget.onEmail,
                            child: const Text(
                              'Or continue with email',
                              style: TextStyle(
                                color: Color(0xFFA79B8A),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _bubbles(double h) {
    const List<IconData> icons = <IconData>[
      Icons.local_fire_department_rounded,
      Icons.format_quote_rounded,
      Icons.check_circle_rounded,
      Icons.auto_stories_rounded,
    ];
    return List<Widget>.generate(icons.length, (int i) {
      final double start = 0.28 + i * 0.09;
      return AnimatedBuilder(
        animation: _fx,
        builder: (BuildContext context, Widget? _) {
          final double progress = ((_fx.value - start) / 0.5).clamp(0.0, 1.0);
          if (progress <= 0 || progress >= 1.0) return const SizedBox.shrink();
          final double t = Curves.easeOutQuad.transform(progress);
          final double left = 40 + i * (i % 2 == 0 ? 62 : 74) + 12 * t;
          final double opacity = ((1.0 - progress) * 0.95).clamp(0.0, 1.0);
          return Positioned(
            left: left,
            bottom: -40 + (h * 0.55 + 40) * t,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 52 - i * 4,
                height: 52 - i * 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2A2015).withValues(alpha: 0.85),
                  border: Border.all(
                    color: const Color(0xFFFFC174).withValues(alpha: 0.4),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFFFC174).withValues(alpha: 0.22),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Icon(
                  icons[i],
                  color: const Color(0xFFFFC174),
                  size: 22 - i * 2,
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

/// The resolved brand mark: flame in a soft amber ring.
class _FlameMark extends StatelessWidget {
  const _FlameMark({this.size = 60});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: <Color>[Color(0xFF3D2A08), Color(0xFF1B140D)],
        ),
        border: Border.all(
          color: const Color(0xFFFFC174).withValues(alpha: 0.55),
          width: 1.6,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFFC174).withValues(alpha: 0.28),
            blurRadius: 18,
          ),
        ],
      ),
      child: Icon(
        Icons.local_fire_department_rounded,
        color: const Color(0xFFFFC174),
        size: size * 0.5,
      ),
    );
  }
}

class _SocialPill extends StatelessWidget {
  const _SocialPill({
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border:
                border == Colors.transparent ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: foreground, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screens 4 + 5 - frosted-glass auth forms
// ---------------------------------------------------------------------------
class _AuthForm extends StatefulWidget {
  const _AuthForm({
    super.key,
    required this.isRegister,
    required this.onDone,
    required this.onSwitch,
  });

  final bool isRegister;
  final VoidCallback onDone;
  final VoidCallback onSwitch;

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1B140D),
        content: Text(msg, style: const TextStyle(color: Color(0xFFE5E2E1))),
      ),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String email = _email.text.trim();
    final String password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Fill in every field first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.isRegister) {
        String base = email
            .split('@')
            .first
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
        if (base.length < 3) base = 'mura_$base';
        String username = base;
        for (int attempt = 0; attempt < 4; attempt++) {
          try {
            await api.register(
              username: username,
              email: email,
              password: password,
            );
            break;
          } on ApiException catch (e) {
            final bool taken = e.message.toLowerCase().contains('username');
            if (taken && attempt < 3) {
              username = base +
                  (DateTime.now().millisecondsSinceEpoch % 10000).toString();
              continue;
            }
            rethrow;
          }
        }
        final String display = _name.text.trim();
        if (display.isNotEmpty) {
          try {
            await api.updateMe(<String, dynamic>{'display_name': display});
          } catch (_) {
            // cosmetic - never block onboarding for a nickname
          }
        }
      } else {
        await api.token(username: email, password: password);
      }
      if (!mounted) return;
      widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach the server. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Glowing brand hero mark
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: 90,
                      height: 90,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Color(0x66F59E0B),
                            blurRadius: 40,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const _FlameMark(size: 68),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'MURA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFFC174),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.0,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Personal Discipline & Focus',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFA79B8A),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 28),

              // Segmented Tab Switcher (Log In vs Create Account)
              Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B140D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x26FFC174)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.isRegister ? widget.onSwitch : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: !widget.isRegister
                                ? const Color(0xFF2A2015)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: !widget.isRegister
                                ? Border.all(
                                    color: const Color(0x40FFC174), width: 1)
                                : null,
                          ),
                          child: Text(
                            'Log In',
                            style: TextStyle(
                              color: !widget.isRegister
                                  ? const Color(0xFFFFC174)
                                  : const Color(0xFFA79B8A),
                              fontSize: 14,
                              fontWeight: !widget.isRegister
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: !widget.isRegister ? widget.onSwitch : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: widget.isRegister
                                ? const Color(0xFF2A2015)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: widget.isRegister
                                ? Border.all(
                                    color: const Color(0x40FFC174), width: 1)
                                : null,
                          ),
                          child: Text(
                            'Create Account',
                            style: TextStyle(
                              color: widget.isRegister
                                  ? const Color(0xFFFFC174)
                                  : const Color(0xFFA79B8A),
                              fontSize: 14,
                              fontWeight: widget.isRegister
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Form fields
              if (widget.isRegister) ...<Widget>[
                _GlassField(
                  controller: _name,
                  hint: 'Display Name',
                  icon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
              ],
              _GlassField(
                controller: _email,
                hint: widget.isRegister ? 'Email Address' : 'Email or Username',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _GlassField(
                controller: _password,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: _obscure,
                toggleObscure: () => setState(() => _obscure = !_obscure),
                textInputAction: TextInputAction.done,
              ),
              if (!widget.isRegister)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _toast(
                        'Password reset instructions sent via email link.'),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: Color(0xFFA79B8A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x26FF3B30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x55FF3B30)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFFFB4AB), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: Color(0xFFFFB4AB), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Action button
              _GradientButton(
                label: widget.isRegister ? 'Create Account' : 'Log In',
                busy: _busy,
                onTap: _submit,
              ),
              const SizedBox(height: 24),

              // Micro feature badges
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const <Widget>[
                  _FeatureBadge(
                      icon: Icons.local_fire_department, label: 'Streaks'),
                  SizedBox(width: 12),
                  _FeatureBadge(icon: Icons.flag, label: 'Priorities'),
                  SizedBox(width: 12),
                  _FeatureBadge(icon: Icons.menu_book, label: 'Journal'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill badge for features at the bottom of Auth UI
class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x1A2A2015),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0x1AFFC174)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: const Color(0xFFFFC174), size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA79B8A),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Translucent dark-glass text field with an amber focus ring.
class _GlassField extends StatelessWidget {
  const _GlassField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.toggleObscure,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final VoidCallback? toggleObscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(color: Color(0xFFE5E2E1), fontSize: 15),
      cursorColor: const Color(0xFFFFC174),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6E6052), fontSize: 14.5),
        prefixIcon: Icon(icon, color: const Color(0xFFA08E7A), size: 20),
        suffixIcon: toggleObscure == null
            ? null
            : IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF6E6052),
                  size: 20,
                ),
                onPressed: toggleObscure,
              ),
        filled: true,
        fillColor: const Color(0xB317120D),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              BorderSide(color: const Color(0xFF534434).withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFFC174), width: 1.3),
        ),
      ),
    );
  }
}

/// Primary amber-gradient action button.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.7 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFFF59E0B), Color(0xFFFFC174)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Color(0xFF472A00), strokeWidth: 2.4),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF472A00),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
