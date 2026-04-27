import 'dart:async';
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
  
  static const String _androidPackageName = 'com.example.phan_mem_quan_ly_can_ho';

  /// Check if an update is available (works on all platforms)
  Future<bool> isUpdateAvailable() async {
    debugPrint('🔍 UpdateService.isUpdateAvailable() called');
    
    try {
      if (Platform.isAndroid) {
        debugPrint('📱 Platform: Android');
        return await _checkAndroidUpdate();
      } else if (Platform.isIOS) {
        debugPrint('📱 Platform: iOS');
        return await _checkVersionFromBackend();
      } else if (Platform.isWindows) {
        debugPrint('💻 Platform: Windows');
        return await _checkVersionFromBackend();
      } else {
        debugPrint('❓ Platform: Unknown');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error in isUpdateAvailable: $e');
      return false;
    }
  }

  /// Perform update based on platform
  Future<bool> performUpdate({void Function(double)? onProgress}) async {
    try {
      if (Platform.isAndroid) {
        return await performFlexibleUpdate();
      } else if (Platform.isIOS) {
        return await _openAppStore();
      } else if (Platform.isWindows) {
        return await performWindowsUpdateWithProgress(
          onProgress ?? (_) {}, // no-op if no callback provided
        );
      } else {
        return false;
      }
    } catch (e) {
      debugPrint('Error performing update: $e');
      return false;
    }
  }

  Future<bool> performWindowsUpdateWithProgress(
    void Function(double progress) onProgress,
  ) async {
    try {
      final savePath = '${Directory.systemTemp.path}\\app_update_installer.exe';
      final url = 'https://github.com/hung148/apartment_management_app_version/releases/latest/download/installer.exe';

      final file = File(savePath);
      if (await file.exists()) await file.delete();

      debugPrint('⬇️ Starting curl download...');

      // curl for fast, reliable download
      final result = await Process.run(
        'curl.exe',
        [
          '-L',
          '-o', savePath,
          '--max-time', '300',
          '--connect-timeout', '30',
          '--silent',
          '--show-error',
          '--fail',
          url,
        ],
        runInShell: false,
      ).timeout(
        const Duration(minutes: 6),
        onTimeout: () => throw TimeoutException('Download timed out'),
      );

      debugPrint('📦 curl exit code: ${result.exitCode}');
      if (result.stderr.toString().isNotEmpty) {
        debugPrint('📦 curl stderr: ${result.stderr}');
      }

      if (result.exitCode != 0) {
        debugPrint('❌ curl failed: ${result.stderr}');
        return false;
      }

      if (!await file.exists()) {
        debugPrint('❌ File not found after download');
        return false;
      }

      final fileSize = await file.length();
      debugPrint('✅ Downloaded $fileSize bytes to $savePath');

      if (fileSize < 100 * 1024) {
        debugPrint('❌ File too small: $fileSize bytes');
        await file.delete();
        return false;
      }

      onProgress(1.0);

      debugPrint('🚀 Launching installer with elevation...');

      // PowerShell only for UAC elevation
      await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Start-Process -FilePath "$savePath" -ArgumentList "/S" -Verb RunAs',
        ],
        runInShell: false,
      );

      await Future.delayed(const Duration(milliseconds: 800));
      exit(0);

    } catch (e) {
      debugPrint('❌ Update error: $e');
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

  // ==================== BACKEND VERSION CHECK ====================

  /// Check version from your backend API (works for all platforms)
  Future<bool> _checkVersionFromBackend() async {
    debugPrint('🌐 _checkVersionFromBackend() started');
    
    try {
      debugPrint('📦 Getting package info...');
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = packageInfo.buildNumber;
      debugPrint('✅ Current version: $currentVersion ($currentBuildNumber)');

      debugPrint('🌐 Making HTTP request in isolate to $_versionCheckUrl');
      
      // Use compute to run HTTP request in separate isolate (prevents UI blocking)
      final responseData = await compute(_fetchVersionData, _versionCheckUrl);
      
      debugPrint('📥 HTTP response received from isolate');

      if (responseData == null) {
        debugPrint('⚠️ Failed to fetch version data');
        return false;
      }

      debugPrint('📄 Parsing JSON...');
      final data = json.decode(responseData);
      debugPrint('✅ JSON parsed successfully');

      String latestVersion;
      String latestBuildNumber;

      if (Platform.isIOS) {
        latestVersion = data['ios']['version'];
        latestBuildNumber = data['ios']['build_number'];
      } else if (Platform.isAndroid) {
        latestVersion = data['android']['version'];
        latestBuildNumber = data['android']['build_number'];
      } else if (Platform.isWindows) {
        latestVersion = data['windows']['version'];
        latestBuildNumber = data['windows']['build_number'];
      } else {
        return false;
      }

      debugPrint('📊 Latest version: $latestVersion ($latestBuildNumber)');

      final isNewer = _isNewerVersion(
        currentVersion,
        currentBuildNumber,
        latestVersion,
        latestBuildNumber,
      );
      
      debugPrint('🏁 Version comparison result: isNewer=$isNewer');
      return isNewer;
      
    } on SocketException catch (e) {
      debugPrint('🔌 SocketException: $e');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('⏱️ TimeoutException: $e');
      return false;
    } on FormatException catch (e) {
      debugPrint('📄 FormatException: $e');
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      return false;
    }
  }

  /// Static method to fetch version data (runs in isolate)
  /// This must be a top-level function or static method for compute()
  static Future<String?> _fetchVersionData(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          throw TimeoutException('Connection timeout');
        },
      );

      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (e) {
      // Return null on any error
      return null;
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