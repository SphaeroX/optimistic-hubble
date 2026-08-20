import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/ble_service.dart';

class DeviceScannerSheet extends StatelessWidget {
  final BleService bleService;

  const DeviceScannerSheet({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bleService,
      builder: (context, _) {
        final devices = bleService.discoveredDevices;
        final isScanning = bleService.isScanning;

        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted.withAlpha(77),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Available BLE Peripherals',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (isScanning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, color: AppTheme.primaryCyan),
                      onPressed: () => bleService.startScan(),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Mock Button for quick PC testing
              OutlinedButton.icon(
                onPressed: () {
                  bleService.enableMockMode();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.developer_mode, size: 18),
                label: const Text('Simulate Xiao Device (PC Test)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentGreen,
                  side: const BorderSide(color: AppTheme.accentGreen),
                ),
              ),
              const SizedBox(height: 12),

              // Device List
              if (devices.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      isScanning
                          ? 'Searching for nearby Xiao ESP32-C3...\n(Service UUID: 19b10000-e8f2-537e-4f6c-d104768a1214)'
                          : 'No devices found. Tap refresh or use simulation.',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(color: Color(0xFF243248)),
                    itemBuilder: (context, index) {
                      final dev = devices[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: dev.isXiaoDevice
                              ? AppTheme.primaryCyan.withAlpha(51)
                              : AppTheme.cardDark,
                          child: Icon(
                            dev.isXiaoDevice ? Icons.mic : Icons.bluetooth,
                            color: dev.isXiaoDevice ? AppTheme.primaryCyan : AppTheme.textMuted,
                          ),
                        ),
                        title: Text(
                          dev.name,
                          style: TextStyle(
                            fontWeight: dev.isXiaoDevice ? FontWeight.bold : FontWeight.normal,
                            color: dev.isXiaoDevice ? Colors.white : AppTheme.textMuted,
                          ),
                        ),
                        subtitle: Text(
                          'RSSI: ${dev.rssi} dBm | ID: ${dev.id}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        trailing: ElevatedButton(
                          onPressed: bleService.isConnecting
                              ? null
                              : () {
                                  bleService.connect(dev);
                                  Navigator.of(context).pop();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: dev.isXiaoDevice ? AppTheme.primaryCyan : AppTheme.cardDark,
                            foregroundColor: dev.isXiaoDevice ? Colors.black : Colors.white,
                          ),
                          child: Text(bleService.isConnecting && bleService.connectedDevice?.id == dev.id ? 'Connecting...' : 'Connect'),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
