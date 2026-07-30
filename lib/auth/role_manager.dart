import 'dart:convert';

class AppRoles {
  static const String student = 'student';
  static const String teacher = 'teacher';
  static const String coordinator = 'academic_coordinator';
  static const String superadmin = 'superadmin';
  static const String accounts = 'accounts';
  static const String hr = 'hr';
  static const String transport = 'transport';
  static const String driver = 'driver';
  static const String examination = 'examination';
  static const String frontoffice = 'frontoffice';

  static const List<String> mobileRolePriority = [
    superadmin,
    frontoffice,
    accounts,
    hr,
    transport,
    driver,
    examination,
    coordinator,
    teacher,
    student,
  ];

  static String normalize(String? role) {
    final value = (role ?? '').trim().toLowerCase().replaceAll('-', '_');

    switch (value) {
      case 'super admin':
      case 'super_admin':
      case 'superadmin':
        return superadmin;
      case 'account':
      case 'accounts':
      case 'accountant':
      case 'finance':
      case 'fees':
        return accounts;
      case 'hr':
      case 'human resources':
      case 'human_resources':
        return hr;
      case 'transport':
      case 'transportation':
        return transport;
      case 'driver':
      case 'transport_driver':
        return driver;
      case 'examination':
      case 'exam':
      case 'exams':
        return examination;
      case 'front office':
      case 'front_office':
      case 'frontoffice':
        return frontoffice;
      case 'coordinator':
      case 'academic coordinator':
      case 'academic_coordinator':
        return coordinator;
      case 'teacher':
      case 'faculty':
        return teacher;
      case 'student':
      case 'parent':
        return student;
      default:
        return value;
    }
  }

  static bool isMobileSupported(String role) {
    return mobileRolePriority.contains(normalize(role));
  }

  static bool isStaff(String role) {
    final normalized = normalize(role);
    return normalized == teacher ||
        normalized == coordinator ||
        normalized == superadmin ||
        normalized == accounts ||
        normalized == hr ||
        normalized == transport ||
        normalized == driver ||
        normalized == examination ||
        normalized == frontoffice;
  }

  static String label(String role) {
    switch (normalize(role)) {
      case superadmin:
        return 'Super Admin';
      case accounts:
        return 'Accounts';
      case hr:
        return 'HR';
      case transport:
        return 'Transport';
      case driver:
        return 'Transport Driver';
      case examination:
        return 'Examination';
      case frontoffice:
        return 'Front Office';
      case coordinator:
        return 'Coordinator';
      case teacher:
        return 'Teacher';
      case student:
        return 'Student';
      default:
        final normalized = normalize(role);
        if (normalized.isEmpty) return 'User';
        return normalized
            .split('_')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ');
    }
  }

  static String dashboardRoute(String role) {
    switch (normalize(role)) {
      case superadmin:
        return '/superadmin';
      case accounts:
        return '/accounts';
      case hr:
        return '/hr';
      case transport:
        return '/transport';
      case driver:
        return '/driver';
      case examination:
        return '/examination';
      case frontoffice:
        return '/frontoffice';
      case coordinator:
        return '/coordinator';
      case teacher:
        return '/teacher';
      case student:
      default:
        return '/dashboard';
    }
  }

  static List<String> supportedFrom(List<String> roles) {
    final normalized = roles.map(normalize).where((role) => role.isNotEmpty);
    final unique = <String>{...normalized};
    return mobileRolePriority.where(unique.contains).toList();
  }

  static String defaultMobileRole(List<String> roles, {String fallback = ''}) {
    final supported = supportedFrom(roles);
    if (supported.isNotEmpty) return supported.first;

    final normalizedFallback = normalize(fallback);
    if (normalizedFallback.isNotEmpty) return normalizedFallback;

    return roles.isNotEmpty ? normalize(roles.first) : '';
  }

  static List<String> extractRoles(Map<String, dynamic> data, dynamic user) {
    final values = <String>[];

    void addRole(dynamic raw) {
      if (raw == null) return;

      if (raw is String) {
        final role = normalize(raw);
        if (role.isNotEmpty) values.add(role);
        return;
      }

      if (raw is Map) {
        addRole(raw['slug'] ?? raw['name'] ?? raw['role'] ?? raw['code']);
        return;
      }

      final role = normalize(raw.toString());
      if (role.isNotEmpty && role != 'null') values.add(role);
    }

    void addRoles(dynamic raw) {
      if (raw is List) {
        for (final item in raw) {
          addRole(item);
        }
      } else {
        addRole(raw);
      }
    }

    addRoles(data['roles'] ?? data['Roles']);
    addRole(data['role'] ?? data['activeRole']);

    if (user is Map) {
      addRoles(user['roles'] ?? user['Roles']);
      addRole(user['role'] ?? user['activeRole']);
    }

    return values.toSet().toList();
  }

  static List<String> decodeStoredRoles(String? stored) {
    if (stored == null || stored.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(stored);
      if (decoded is List) {
        return decoded.map((role) => normalize(role.toString())).toList();
      }
    } catch (_) {
      // Fall back to comma-separated legacy storage.
    }

    return stored
        .split(',')
        .map(normalize)
        .where((role) => role.isNotEmpty)
        .toList();
  }
}
