import 'dart:io';

/// Central place for platform capability checks.
///
/// Most `Platform.isWindows` checks scattered through this app really mean
/// "desktop". macOS is a planned target, so new code should ask about a
/// capability here rather than naming an operating system directly.
abstract final class PlatformSupport {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Desktop platforms get a native "save as" dialog; mobile goes through the
  /// system document picker. Both are handled by file_picker.
  static bool get hasNativeSaveDialog => isDesktop;

  /// A local loopback HTTP server can be bound (used by the Windows OAuth
  /// flow today, and the planned LAN device-to-device transfer).
  ///
  /// On macOS this additionally requires the `com.apple.security.network.server`
  /// entitlement, which is currently only present in DebugProfile.entitlements.
  static bool get canBindLocalServer => isDesktop;

  /// Foreground service keeping the timer alive in the background.
  static bool get hasForegroundTimerService => Platform.isAndroid;

  /// Local notifications are wired for Android today. macOS support exists in
  /// flutter_local_notifications via DarwinInitializationSettings but is not
  /// initialised yet.
  static bool get hasLocalNotifications => Platform.isAndroid;

  /// Desktop window sizing/positioning via window_manager.
  static bool get hasWindowManager => isDesktop;

  /// Short label used in exported backup metadata.
  static String get name {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
