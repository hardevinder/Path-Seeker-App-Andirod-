// lib/screens/login_screen.dart
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/role_manager.dart';
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
  final String logoAsset = 'assets/logo.png';

  String get apiBase => baseUrl;

  /// Clear all user/session/student-specific local values.
  /// This is important when the same Android device is used for multiple logins.
  Future<void> _clearLocalSession(SharedPreferences prefs) async {
    final keysToRemove = [
      // Auth/session
      'authToken',
      'roles',
      'activeRole',
      'selectedRole',
      'role',
      'userRole',
      'currentUser',

      // Basic user identity
      'username',
      'userId',
      'user_id',
      'name',
      'email',

      // Student/family/sibling values
      'family',
      'selectedStudentAdmissionNumber',
      'activeStudentAdmission',
      'admissionNumber',
      'admission_number',
      'studentId',
      'student_id',

      // Teacher/staff values
      'employeeId',
      'employee_id',
      'teacherId',
      'teacher_id',

      // Cached user-specific data
      'notifications',
      'pits_notifications',
    ];

    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  Future<Map<String, String>> authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  List<String> _mobileSupportedRoles(List<String> roles) {
    return AppRoles.supportedFrom(roles);
  }

  Future<String> _resolveActiveMobileRole({
    required List<String> roles,
    required String fallbackRole,
  }) async {
    final mobileRoles = _mobileSupportedRoles(roles);

    if (mobileRoles.isEmpty) {
      return fallbackRole;
    }

    if (mobileRoles.length == 1) {
      return mobileRoles.first;
    }

    if (!mounted) {
      return mobileRoles.first;
    }

    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Choose login role'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: mobileRoles.map((role) {
              final normalized = AppRoles.normalize(role);
              final icon = normalized == AppRoles.superadmin
                  ? Icons.security_rounded
                  : normalized == AppRoles.hr
                      ? Icons.people_rounded
                      : normalized == AppRoles.transport
                          ? Icons.directions_bus_rounded
                          : normalized == AppRoles.driver
                              ? Icons.drive_eta_rounded
                              : normalized == AppRoles.examination
                                  ? Icons.school
                                  : normalized == AppRoles.coordinator
                                      ? Icons.manage_accounts_rounded
                                      : normalized == AppRoles.teacher
                                          ? Icons.school
                                          : Icons.person;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(AppRoles.label(role)),
                onTap: () => Navigator.of(dialogContext).pop(role),
              );
            }).toList(),
          ),
        );
      },
    );

    return selected ?? mobileRoles.first;
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

      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        data = decoded is Map<String, dynamic>
            ? decoded
            : {'success': false, 'message': 'Invalid server response'};
      } catch (_) {
        data = {
          'success': false,
          'message': 'Invalid server response',
          'raw': response.body,
        };
      }

      if (response.statusCode == 200 &&
          data['token'] != null &&
          data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();

        // Very important:
        // Clear old logged-in user's data before saving new user data.
        await _clearLocalSession(prefs);

        final token = data['token'].toString();
        final user = data['user'];

        await prefs.setString('authToken', token);

        // Basic user info
        final username = user?['username']?.toString() ?? login;
        final userId = user?['id']?.toString() ?? '';
        final name = user?['name']?.toString() ?? '';
        final email = user?['email']?.toString() ?? '';

        await prefs.setString('username', username);
        await prefs.setString('userId', userId);
        await prefs.setString('name', name);

        if (email.isNotEmpty) {
          await prefs.setString('email', email);
        }

        // Save current user JSON also, useful if AuthProvider/AuthService reads it.
        try {
          await prefs.setString('currentUser', jsonEncode(user ?? {}));
        } catch (_) {
          // Ignore non-serializable user data.
        }

        // Roles and default role
        final List<String> roleOrder = [
          "superadmin",
          "admin",
          "accounts",
          "hr",
          "academic_coordinator",
          "teacher",
          "student",
          "driver",
        ];

        final roles = AppRoles.extractRoles(data, user);

        final defaultRole = roleOrder.firstWhere(
          (r) => roles.contains(r),
          orElse: () => roles.isNotEmpty ? roles.first : '',
        );
        final activeRole = await _resolveActiveMobileRole(
          roles: roles,
          fallbackRole: defaultRole,
        );

        await prefs.setString('roles', jsonEncode(roles));
        await prefs.setString('activeRole', activeRole);
        await prefs.setString('selectedRole', activeRole);

        // Save family & active student like React.
        // Also save selectedStudentAdmissionNumber because Dashboard reads that first.
        if (data['family'] != null) {
          await prefs.setString('family', jsonEncode(data['family']));

          final admission = data['family']?['student']?['admission_number'] ??
              data['family']?['student']?['admissionNumber'] ??
              user?['admission_number'] ??
              user?['admissionNumber'] ??
              user?['username'] ??
              login;

          final admissionText = admission.toString().trim();

          if (admissionText.isNotEmpty) {
            await prefs.setString('activeStudentAdmission', admissionText);
            await prefs.setString(
              'selectedStudentAdmissionNumber',
              admissionText,
            );
            await prefs.setString('admissionNumber', admissionText);
          }

          final studentId = data['family']?['student']?['id'] ??
              data['family']?['student']?['student_id'];

          if (studentId != null) {
            await prefs.setString('studentId', studentId.toString());
          }
        } else {
          await prefs.remove('family');
          await prefs.remove('activeStudentAdmission');
          await prefs.remove('selectedStudentAdmissionNumber');

          // For direct student login without family object.
          if (activeRole == 'student') {
            final admission = user?['admission_number'] ??
                user?['admissionNumber'] ??
                user?['username'] ??
                login;

            final admissionText = admission.toString().trim();

            if (admissionText.isNotEmpty) {
              await prefs.setString('activeStudentAdmission', admissionText);
              await prefs.setString(
                'selectedStudentAdmissionNumber',
                admissionText,
              );
              await prefs.setString('admissionNumber', admissionText);
            }

            final studentId = user?['studentId'] ??
                user?['student_id'] ??
                user?['Student_ID'];

            if (studentId != null) {
              await prefs.setString('studentId', studentId.toString());
            }
          }
        }

        // Save teacher/staff identifiers if present.
        final employeeId = user?['employeeId'] ?? user?['employee_id'];
        if (employeeId != null) {
          await prefs.setString('employeeId', employeeId.toString());
        }

        final teacherId = user?['teacherId'] ?? user?['teacher_id'];
        if (teacherId != null) {
          await prefs.setString('teacherId', teacherId.toString());
        }

        // Register this installation after authentication. Notification setup
        // runs before login, when no bearer token exists, so this post-login
        // sync is required for first-time users and fresh installations.
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();

          if (fcmToken != null && fcmToken.trim().isNotEmpty) {
            await prefs.setString('fcmToken', fcmToken);

            final cleanBase = apiBase.replaceAll(RegExp(r'/+$'), '');
            final registerResponse = await http
                .post(
                  Uri.parse('$cleanBase/api/notifications/register-device'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'Authorization': 'Bearer $token',
                  },
                  body: jsonEncode({
                    'token': fcmToken,
                    'platform': Platform.isAndroid ? 'android' : 'ios',
                    'deviceName':
                        Platform.isAndroid ? 'SMCIS Android' : 'SMCIS iOS',
                    'systemVersion': Platform.operatingSystemVersion,
                  }),
                )
                .timeout(const Duration(seconds: 20));

            final registered = registerResponse.statusCode >= 200 &&
                registerResponse.statusCode < 300;
            await prefs.setBool('fcmTokenSynced', registered);

            if (registered) {
              debugPrint('FCM device registered after login.');
            } else {
              debugPrint(
                'FCM device registration failed: '
                '${registerResponse.statusCode} ${registerResponse.body}',
              );
            }
          }
        } catch (e) {
          await prefs.setBool('fcmTokenSynced', false);
          debugPrint('FCM save failed: $e');
        }

        if (!mounted) return;

        // Navigate by role and clear previous stack.
        if (AppRoles.isMobileSupported(activeRole) || activeRole.isEmpty) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoles.dashboardRoute(activeRole),
            (route) => false,
          );
        } else {
          await _clearLocalSession(prefs);
          _showError(
            'This app does not currently support '
            'Please use the web portal for ${activeRole.toUpperCase()} access.',
          );
        }
      } else {
        final serverMsg =
            data['message'] ?? data['error'] ?? 'Invalid credentials.';
        _showError(serverMsg.toString());
      }
    } catch (e) {
      _showError('Login failed: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    try {
      if (token.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('$apiBase/users/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        } catch (_) {
          // Ignore server logout error and still clear local session.
        }
      }
    } finally {
      await _clearLocalSession(prefs);

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;

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
            child: const Text(
              "OK",
              style: TextStyle(color: Colors.blueAccent),
            ),
            onPressed: () => Navigator.pop(context),
          ),
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
                        child: const Icon(
                          Icons.school,
                          size: 50,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Title
                  const Text(
                    "SMCIS",
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 28,
                    ),
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
                        TextField(
                          controller: _loginController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            hint: "Username or Email",
                            icon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 14),
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
                              onPressed: () {
                                setState(() => showPassword = !showPassword);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: remember,
                                    activeColor: Colors.blueAccent,
                                    onChanged: (val) {
                                      setState(() => remember = val ?? true);
                                    },
                                  ),
                                  const Flexible(
                                    child: Text(
                                      "Remember me",
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showError(
                                "Forgot Password? Please contact admin.",
                              ),
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
                    "© 2025 Seth Malook Chand International School",
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
}
