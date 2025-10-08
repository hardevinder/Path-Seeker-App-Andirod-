import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../constants/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool loading = false;
  bool remember = true;
  bool showPassword = false;
  String errorMessage = '';

  final String backgroundAsset = 'assets/Tips_Background.png';
  final String logoAsset = 'assets/tpis_logo.png';

  Future<void> handleLogin() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text.trim();

    if (login.isEmpty || password.isEmpty) {
      _showError("Please enter both login and password.");
      return;
    }

    setState(() {
      loading = true;
      errorMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'login': login, 'password': password}),
      );

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('application/json')) {
        _showError('Invalid server response (not JSON).');
        return;
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('authToken', data['token']);
        await prefs.setString('username', data['user']['username'] ?? login);
        await prefs.setString('userId', data['user']['id'].toString());
        await prefs.setString('roles', jsonEncode(data['roles'] ?? []));

        // Default role logic
        final List<String> roleOrder = [
          "superadmin",
          "admin",
          "accounts",
          "hr",
          "academic_coordinator",
          "teacher",
          "student"
        ];
        final roles = List<String>.from(data['roles'] ?? []);
        final lowerRoles = roles.map((r) => r.toLowerCase()).toList();
        final defaultRole = roleOrder.firstWhere(
          (r) => lowerRoles.contains(r),
          orElse: () => lowerRoles.isNotEmpty ? lowerRoles.first : '',
        );
        await prefs.setString('activeRole', defaultRole);

        // FCM Token Save
        String userId = data['user']['id'].toString();
        String? fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await FirebaseFirestore.instance.collection('users').doc(userId).set({
            'fcmToken': fcmToken,
            'role': defaultRole,
          }, SetOptions(merge: true));
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
            FirebaseFirestore.instance.collection('users').doc(userId).update({
              'fcmToken': newToken,
            });
          });
        }

        if (!mounted) return;
        final redirectRoute =
            defaultRole == 'accounts' ? '/accountsDashboard' : '/dashboard';
        Navigator.of(context).pushReplacementNamed(redirectRoute);
      } else {
        _showError(data['error'] ?? 'Invalid credentials.');
      }
    } catch (e) {
      _showError('Login failed: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  void _showError(String msg) {
    setState(() => errorMessage = msg);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "Login Failed",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          msg,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text("OK", style: TextStyle(color: Colors.blueAccent)),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Soft background image
          Positioned.fill(
            child: Image.asset(
              backgroundAsset,
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.3), // less dark background
              colorBlendMode: BlendMode.darken,
            ),
          ),

          // Overlay for slight depth
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.5),
                    Colors.black.withOpacity(0.4),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // Main content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  ClipOval(
                    child: Image.asset(
                      logoAsset,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(45),
                        ),
                        child: const Icon(Icons.school,
                            size: 50, color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // TPIS title
                  const Text(
                    "TPIS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      shadows: [
                        Shadow(
                          blurRadius: 12,
                          color: Colors.blueAccent,
                          offset: Offset(1, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Glass-style Sign In box
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 28),
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Sign in",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Username
                        TextField(
                          controller: _loginController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            hint: "Username or Email",
                            icon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Password
                        TextField(
                          controller: _passwordController,
                          style: const TextStyle(color: Colors.white),
                          obscureText: !showPassword,
                          decoration: _inputDecoration(
                            hint: "Password",
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.white70,
                              ),
                              onPressed: () =>
                                  setState(() => showPassword = !showPassword),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Remember + Forgot
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: remember,
                                  activeColor: Colors.blueAccent,
                                  onChanged: (val) =>
                                      setState(() => remember = val ?? true),
                                ),
                                const Text(
                                  "Remember me",
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () => _showError(
                                  "Forgot Password? Please contact admin."),
                              child: const Text(
                                "Forgot password?",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),

                        if (errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              errorMessage,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Login Button
                        ElevatedButton(
                          onPressed: loading ? null : handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 5,
                          ),
                          child: loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  const Text(
                    "© 2025 The Pathseekers International School",
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white60),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Colors.blueAccent),
      ),
    );
  }
}
