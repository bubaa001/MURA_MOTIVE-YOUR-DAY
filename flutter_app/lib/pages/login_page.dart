import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart'; // ignore: unused_import
import '../theme.dart'; // ignore: unused_import

/// MURA - Login screen (Obsidian & Amber).
///
/// Calls [ApiClient.instance.token], which exchanges username/password for
/// JWTs, stores them, and resolves with the fresh profile on success.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _api = ApiClient.instance;

  bool _busy = false;
  bool _registerMode = false;
  String? _error;

  // Obsidian & Amber palette (kept local so this page compiles standalone).
  static const Color _bg = Color(0xFF0D0B09);
  static const Color _card = Color(0xFF17120D);
  static const Color _field = Color(0xFF1E1811);
  static const Color _amber = Color(0xFFFFC174);
  static const Color _amberDeep = Color(0xFFF59E0B);
  static const Color _onAmber = Color(0xFF472A00);
  static const Color _text = Color(0xFFE5E2E1);
  static const Color _textDim = Color(0xFFA08E7A);
  static const Color _outline = Color(0xFF534434);
  static const Color _errorRed = Color(0xFFFFB4AB);

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registerMode) {
        await _api.register(
          username: _usernameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await _api.token(
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/today');
    } catch (e) {
      if (!mounted) return;
      final String detail =
          e is ApiException ? e.message : 'Could not reach the server.';
      setState(() {
        _busy = false;
        _error = _registerMode
            ? 'Could not create account - $detail'
            : 'Login failed - $detail';
      });
    }
  }

  InputDecoration _deco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _textDim, fontSize: 14),
      prefixIcon: Icon(icon, color: _textDim, size: 20),
      filled: true,
      fillColor: _field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _amberDeep, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _errorRed, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _errorRed, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFC174), Color(0xFFF59E0B)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x33F59E0B),
                            blurRadius: 36,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_fire_department,
                        size: 38,
                        color: _onAmber,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      'MURA',
                      style: TextStyle(
                        color: _text,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'DISCIPLINE \u00B7 EVERY SINGLE DAY',
                      style: TextStyle(
                        color: _textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _usernameCtrl,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          style: const TextStyle(color: _text, fontSize: 15),
                          decoration:
                              _deco('Username', Icons.person_outline_rounded),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        if (_registerMode) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            style: const TextStyle(color: _text, fontSize: 15),
                            decoration:
                                _deco('Email', Icons.alternate_email_rounded),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          autofillHints: const [AutofillHints.password],
                          style: const TextStyle(color: _text, fontSize: 15),
                          decoration:
                              _deco('Password', Icons.lock_outline_rounded),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _errorRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _amberDeep,
                              foregroundColor: _onAmber,
                              disabledBackgroundColor: const Color(0xFF54430F),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: _onAmber,
                                    ),
                                  )
                                : Text(_registerMode
                                    ? 'CREATE ACCOUNT'
                                    : 'SIGN IN'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _registerMode = !_registerMode;
                                _error = null;
                              }),
                      child: Text(
                        _registerMode
                            ? 'Have an account? Sign in'
                            : 'New here? Create your account',
                        style: const TextStyle(color: _amber, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'dev login: buba / mura',
                      style: TextStyle(color: Color(0xFF5C5044), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
