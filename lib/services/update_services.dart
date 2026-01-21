import 'package:in_app_update/in_app_update.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

/// Service to handle app updates across all platforms
class UpdateService {
  static const String _versionCheckUrl = 'https://hung148.github.io/apartment_management_app_version/version.json';
  
  static const String _appStoreId = 'YOUR_APP_STORE_ID';
  
  static const String _androidPackageName = 'com.example.apartment_management_project_2';

  /// Check if an update is available (works on all platforms)
  Future<bool> isUpdateAvailable() async {
    try {
      if (Platform.isAndroid) {
        // Android: Use Google Play Store in-app updates
        return await _checkAndroidUpdate();
      } else if (Platform.isIOS) {
        // iOS: Check version from your backend
        return await _checkVersionFromBackend();
      } else if (Platform.isWindows) {
        // Windows: Check version from your backend
        return await _checkVersionFromBackend();
      } else {
        // Other platforms: Check version from your backend
        return await _checkVersionFromBackend();
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return false;
    }
  }

  /// Perform update based on platform
  Future<bool> performUpdate() async {
    try {
      if (Platform.isAndroid) {
        return await performFlexibleUpdate();
      } else if (Platform.isIOS) {
        return await _openAppStore();
      } else if (Platform.isWindows) {
        return await _openWindowsDownloadPage();
      } else {
        debugPrint('Update not supported on this platform');
        return false;
      }
    } catch (e) {
      debugPrint('Error performing update: $e');
      return false;
    }
  }

  // ==================== ANDROID METHODS ====================

  /// Check for Android update via Play Store
  Future<bool> _checkAndroidUpdate() async {
    try {
      AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();
      return updateInfo.updateAvailability == UpdateAvailability.updateAvailable;
    } catch (e) {
      debugPrint('Error checking Android update: $e');
      return false;
    }
  }

  /// Perform flexible update (Android only - user can continue using app)
  Future<bool> performFlexibleUpdate() async {
    if (!Platform.isAndroid) return false;
    
    try {
      await InAppUpdate.startFlexibleUpdate();
      await InAppUpdate.completeFlexibleUpdate();
      return true;
    } catch (e) {
      debugPrint('Error performing flexible update: $e');
      return false;
    }
  }

  /// Perform immediate update (Android only - forces user to update)
  Future<bool> performImmediateUpdate() async {
    if (!Platform.isAndroid) return false;
    
    try {
      await InAppUpdate.performImmediateUpdate();
      return true;
    } catch (e) {
      debugPrint('Error performing immediate update: $e');
      return false;
    }
  }

  // ==================== iOS METHODS ====================

  /// Open App Store (iOS only)
  Future<bool> _openAppStore() async {
    if (!Platform.isIOS) return false;
    
    try {
      final url = Uri.parse('https://apps.apple.com/app/id$_appStoreId');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error opening App Store: $e');
      return false;
    }
  }

  // ==================== WINDOWS METHODS ====================

  /// Open Windows download page
  Future<bool> _openWindowsDownloadPage() async {
    if (!Platform.isWindows) return false;
    
    try {
      // Replace with your actual Windows download URL
      final url = Uri.parse('https://github.com/hung148/apartment_management_app_version/releases/latest');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error opening download page: $e');
      return false;
    }
  }

  // ==================== BACKEND VERSION CHECK ====================

  /// Check version from your backend API (works for all platforms)
  Future<bool> _checkVersionFromBackend() async {
    try {
      // Get current app version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      String currentBuildNumber = packageInfo.buildNumber;

      // Make API request to check latest version
      final response = await http.get(Uri.parse(_versionCheckUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Platform-specific version check
        String latestVersion;
        String latestBuildNumber;
        
        if (Platform.isIOS) {
          latestVersion = data['ios']['version'];
          latestBuildNumber = data['ios']['build_number'];
        } else if (Platform.isWindows) {
          latestVersion = data['windows']['version'];
          latestBuildNumber = data['windows']['build_number'];
        } else if (Platform.isAndroid) {
          latestVersion = data['android']['version'];
          latestBuildNumber = data['android']['build_number'];
        } else {
          return false;
        }

        // Compare versions
        return _isNewerVersion(
          currentVersion,
          currentBuildNumber,
          latestVersion,
          latestBuildNumber,
        );
      }
      return false;
    } catch (e) {
      debugPrint('Error checking version from backend: $e');
      return false;
    }
  }

  /// Compare version numbers
  bool _isNewerVersion(
    String currentVersion,
    String currentBuild,
    String latestVersion,
    String latestBuild,
  ) {
    // First compare build numbers (more reliable)
    int currentBuildInt = int.tryParse(currentBuild) ?? 0;
    int latestBuildInt = int.tryParse(latestBuild) ?? 0;

    if (latestBuildInt > currentBuildInt) {
      return true;
    }

    // If build numbers are same, compare version strings
    List<int> currentParts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts = latestVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }

    return false;
  }

  // ==================== UTILITY METHODS ====================

  /// Get current platform name
  String getCurrentPlatform() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Get detailed update info (Android only)
  Future<AppUpdateInfo?> getUpdateInfo() async {
    if (!Platform.isAndroid) return null;
    
    try {
      return await InAppUpdate.checkForUpdate();
    } catch (e) {
      debugPrint('Error getting update info: $e');
      return null;
    }
  }

  /// Get current app version
  Future<String> getCurrentVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      return '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      debugPrint('Error getting current version: $e');
      return 'Unknown';
    }
  }
}