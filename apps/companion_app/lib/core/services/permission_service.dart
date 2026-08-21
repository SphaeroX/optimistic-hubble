import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  PermissionService._();

  /// Requests all necessary permissions for Bluetooth Low Energy,
  /// Location (Android <= 11), Nearby Wi-Fi Devices (Android 13+), and Foreground Notifications.
  static Future<bool> requestAppPermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }

    try {
      final List<Permission> permissionsToRequest = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.nearbyWifiDevices,
        Permission.notification,
      ];

      final Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();

      final bool bluetoothScanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final bool bluetoothConnectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;

      debugPrint('[PermissionService] Permission Request Results: $statuses');

      return bluetoothScanGranted || bluetoothConnectGranted;
    } catch (e) {
      debugPrint('[PermissionService] Error requesting permissions: $e');
      return false;
    }
  }

  /// Checks if all necessary Bluetooth permissions are already granted.
  static Future<bool> checkPermissionsStatus() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    try {
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      return scanStatus.isGranted && connectStatus.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Opens app settings if permissions were permanently denied.
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
