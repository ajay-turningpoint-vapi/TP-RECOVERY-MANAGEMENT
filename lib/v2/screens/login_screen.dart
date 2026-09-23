import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/screens/maintenance_screen.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;
  String? _errorMessage;
  bool _isLoading = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // No SSE while logged out (server requires auth for /api/events), so this
  // is what lets the notice clear itself the moment maintenance ends,
  // instead of requiring a force-quit/reopen.
  Timer? _maintenancePoll;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnimation = Tween<double>(begin: 0, end: 8).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
    _maintenancePoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) context.read<AppStore>().checkMaintenanceStatus();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _shakeController.dispose();
    _maintenancePoll?.cancel();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      _triggerError('Please enter your username and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final store = context.read<AppStore>();
    final error = await store.loginWithApi(username, password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      _triggerError(error);
    }
  }

  void _triggerError(String message) {
    setState(() => _errorMessage = message);
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    // No admin bypass here — Admin signs in through the separate admin app
    // (see lib/main_admin.dart) and turns maintenance off from there, so
    // this screen is a genuine dead end for everyone else while it's on.
    // Same widget SyncFreezeOverlay shows post-login — one maintenance UI
    // in the whole app, never a popup/curtain.
    if (store.maintenanceMode) {
      return const MaintenanceScreen();
    }
    return _buildLoginScreen();
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo area
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0052CC), Color(0xFF3381FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF0052CC).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: const Icon(Icons.shield_outlined, color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'TP-RMS',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48), letterSpacing: -0.5),
              ),
              const SizedBox(height: 6),
              const Text(
                'Recovery Management System',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 40),
              _buildLoginCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (ctx, child) => Transform.translate(
        offset: Offset(_shakeController.isAnimating ? _shakeAnimation.value * ((_shakeController.value * 10).round().isEven ? 1 : -1) : 0, 0),
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sign In',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter your credentials to access your account',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 24),

            // Username field
            _buildLabel('Username'),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: (_) => setState(() => _errorMessage = null),
              style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
              decoration: _inputDecoration(
                hint: 'Your TP-RMS username',
                icon: Icons.person_outline,
                hasError: _errorMessage != null,
              ),
            ),
            const SizedBox(height: 16),

            // Password field
            _buildLabel('Password'),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscureText,
              onChanged: (_) => setState(() => _errorMessage = null),
              onSubmitted: (_) => _handleLogin(),
              style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
              decoration: _inputDecoration(
                hint: 'Enter password',
                icon: Icons.lock_outline,
                hasError: _errorMessage != null,
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: const Color(0xFF64748B),
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
            ),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Sign In button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _handleLogin,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
    );
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon, required bool hasError}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      prefixIcon: Icon(icon, color: hasError ? const Color(0xFFDC2626) : const Color(0xFF2563EB), size: 18),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: hasError ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: hasError ? const Color(0xFFDC2626) : const Color(0xFF2563EB), width: 1.5),
      ),
    );
  }
}
