// lib/screens/login_screen.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  // Helper to get API base (use your constants file)
  String get apiBase => baseUrl; // e.g. 'https://api-pits.edubridgeerp.in'

  // Helper: returns headers including Authorization if token present
  Future<Map<String, String>> authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    final headers = {
      'Content-Type': 'application/json',
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

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
    final deviceInfo = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
            ? 'iOS'
            : Platform.operatingSystem;

    final body = jsonEncode({
      'login': login,
      'password': password,
      'device': deviceInfo,
    });

    final response = await http.post(
      Uri.parse('$apiBase/users/login'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['token'] != null && data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      final token = data['token'] as String;
      await prefs.setString('authToken', token);

      // Basic user info
      await prefs.setString('username', data['user']?['username'] ?? login);
      await prefs.setString('userId', data['user']?['id']?.toString() ?? '');
      await prefs.setString('name', data['user']?['name'] ?? '');

      // Roles and default role
      final List<String> roleOrder = [
        "superadmin", "admin", "accounts", "hr",
        "academic_coordinator", "teacher", "student"
      ];
      final roles = (data['roles'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          [];
      final defaultRole = roleOrder.firstWhere(
        (r) => roles.contains(r),
        orElse: () => roles.isNotEmpty ? roles.first : '',
      );
      await prefs.setString('roles', jsonEncode(roles));
      await prefs.setString('activeRole', defaultRole);

      // ✅ NEW: Save family & active student like React
      if (data['family'] != null) {
        await prefs.setString('family', jsonEncode(data['family']));
        final admission =
            data['family']['student']?['admission_number'] ??
            data['user']?['username'] ??
            login;
        await prefs.setString('activeStudentAdmission', admission.toString());
      } else {
        await prefs.remove('family');
        await prefs.remove('activeStudentAdmission');
      }

      // ✅ Save FCM token to server (unchanged)
      try {
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await http.post(
            Uri.parse('$apiBase/users/save-token'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode({'username': data['user']?['username'] ?? login, 'token': fcmToken}),
          );
        }
      } catch (e) {
        debugPrint('FCM save failed: $e');
      }

      if (!mounted) return;

      // ✅ Navigate by role
      if (defaultRole == 'teacher') {
        Navigator.of(context).pushReplacementNamed('/teacher');
      } else if (defaultRole == 'accounts') {
        Navigator.of(context).pushReplacementNamed('/accountsDashboard');
      } else {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      }
    } else {
      final serverMsg = data['message'] ?? data['error'] ?? 'Invalid credentials.';
      _showError(serverMsg);
    }
  } catch (e) {
    _showError('Login failed: $e');
  } finally {
    if (mounted) setState(() => loading = false);
  }
}


  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      if (token.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('$apiBase/users/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        } catch (e) {
          // ignore server errors, proceed to cleanup
        }
      }
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('authToken');
      await prefs.remove('roles');
      await prefs.remove('username');
      await prefs.remove('userId');
      await prefs.remove('name');
      await prefs.remove('activeRole');
      // Optionally clear FCM token on server if desired (you can add endpoint)
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
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
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Soft background image
          Positioned.fill(
            child: Image.asset(
              backgroundAsset,
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.3),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          // Gradient overlay
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
                        child: const Icon(Icons.school, size: 50, color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Title
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
                  // Login card
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
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
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
                        // Username field
                        TextField(
                          controller: _loginController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            hint: "Username or Email",
                            icon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Password field
                        TextField(
                          controller: _passwordController,
                          style: const TextStyle(color: Colors.white),
                          obscureText: !showPassword,
                          decoration: _inputDecoration(
                            hint: "Password",
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                showPassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.white70,
                              ),
                              onPressed: () => setState(() => showPassword = !showPassword),
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
                                  onChanged: (val) => setState(() => remember = val ?? true),
                                ),
                                const Text("Remember me", style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                            TextButton(
                              onPressed: () => _showError("Forgot Password? Please contact admin."),
                              child: const Text("Forgot password?", style: TextStyle(color: Colors.white70)),
                            ),
                          ],
                        ),
                        if (errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(errorMessage, style: const TextStyle(color: Colors.redAccent)),
                          ),
                        const SizedBox(height: 12),
                        // Login button
                        ElevatedButton(
                          onPressed: loading ? null : handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 5,
                          ),
                          child: loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  "Login",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    "© 2025 The Pathseekers International School",
                    style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 0.5),
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
