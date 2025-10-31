// lib/constants/constants.dart

/// Central place for app-wide constants.
/// This file exposes:
// - `Constants` class with `apiBase`, `appName`, `defaultPadding`
// - top-level aliases `baseUrl`, `appName`, `defaultPadding` for older code
// - `AppConstants` class with `baseUrl` alias for code that expects AppConstants

/// Primary constants container (preferred).
class Constants {
  /// Base URL for your backend API (no trailing slash)
  static const String apiBase = "https://api-pits.edubridgeerp.in";

  /// App display name
  static const String appName = "TPIS";

  /// Default UI padding used across screens
  static const double defaultPadding = 16.0;

  /// Common timeout (ms)
  static const int apiTimeoutMs = 20000;
}

/// Top-level (legacy) aliases kept for backwards compatibility.
/// Some files in the codebase reference `baseUrl`, `appName`, or `defaultPadding`.
const String baseUrl = Constants.apiBase;
const String appName = Constants.appName;
const double defaultPadding = Constants.defaultPadding;

/// Another alias class because some files reference `AppConstants.baseUrl`
class AppConstants {
  static const String baseUrl = Constants.apiBase;
  static const String name = Constants.appName;
  static const double padding = Constants.defaultPadding;
}
