import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../connection/services/ble_service.dart';
import '../services/recording_sync_manager.dart';

class FastTransferSheet extends StatelessWidget {
  final BleService bleService;
  final RecordingSyncManager syncManager;
  final int? targetClipId;

  const FastTransferSheet({
    super.key,
    required this.bleService,
    required this.syncManager,
    this.targetClipId,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: syncManager,
      builder: (context, _) {
        final phase = syncManager.fastTransferPhase;
        final isSyncing = syncManager.isSyncing;
        final isDone = phase == FastTransferPhase.completed;
        final isError = phase == FastTransferPhase.failed || syncManager.errorMessage != null;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF131B2A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryCyan.withAlpha(35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wifi_tethering, color: AppTheme.primaryCyan, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WiFi Fast Transfer',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          targetClipId != null
                              ? 'Syncing Clip #$targetClipId @ > 2.0 MB/s'
                              : 'High-Speed SoftAP Batch Sync (~10x BLE)',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textMuted),
                    onPressed: isSyncing ? null : () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: Color(0xFF243248), height: 1),
              const SizedBox(height: 16),

              // 5-Phase Connection Flow List
              _buildPhaseRow(
                stepNum: 1,
                title: '1. Activating ESP32 Hotspot',
                description: 'BLE command sent • SoftAP starting (192.168.4.1)',
                isActive: phase == FastTransferPhase.activatingHotspot,
                isDone: phase.stepIndex > FastTransferPhase.activatingHotspot.stepIndex,
              ),
              const SizedBox(height: 10),

              _buildPhaseRow(
                stepNum: 2,
                title: '2. Connecting to Wi-Fi',
                description: 'Android WifiNetworkSpecifier link negotiation',
                isActive: phase == FastTransferPhase.connectingWifi,
                isDone: phase.stepIndex > FastTransferPhase.connectingWifi.stepIndex,
              ),
              const SizedBox(height: 10),

              _buildPhaseRow(
                stepNum: 3,
                title: '3. Handshaking & Device Catalog',
                description: 'Verifying HTTP /api/handshake endpoint',
                isActive: phase == FastTransferPhase.handshaking,
                isDone: phase.stepIndex > FastTransferPhase.handshaking.stepIndex,
              ),
              const SizedBox(height: 10),

              _buildPhaseRow(
                stepNum: 4,
                title: '4. Ready for Transfer',
                description: 'High-speed TCP connection established',
                isActive: phase == FastTransferPhase.ready,
                isDone: phase.stepIndex > FastTransferPhase.ready.stepIndex,
              ),
              const SizedBox(height: 10),

              _buildPhaseRow(
                stepNum: 5,
                title: '5. Turbo Transfer',
                description: isSyncing && syncManager.currentSyncFile.isNotEmpty
                    ? '${syncManager.currentSyncFile} • ${(syncManager.syncProgress * 100).toStringAsFixed(0)}%'
                    : 'High-Speed streaming (~2.4 MB/s)',
                trailingText: isSyncing ? (syncManager.currentSpeed ?? '2.4 MB/s') : null,
                isActive: phase == FastTransferPhase.transferring,
                isDone: isDone,
              ),

              const SizedBox(height: 16),

              // Live Progress Bar (if transferring)
              if (isSyncing) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: syncManager.syncProgress.clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFF1C2738),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Error Message Banner (if any)
              if (isError && syncManager.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentRed.withAlpha(35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentRed),
                  ),
                  child: Text(
                    syncManager.errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Auto-Delete Option Checkbox
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: const Text(
                  'Delete from ESP32 storage after successful sync',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                ),
                value: syncManager.autoDeleteAfterSync,
                activeColor: AppTheme.primaryCyan,
                checkColor: Colors.black,
                onChanged: isSyncing ? null : (v) => syncManager.autoDeleteAfterSync = v ?? false,
              ),

              const SizedBox(height: 12),

              // Action Buttons
              if (isDone)
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Transfer Complete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                )
              else if (isSyncing)
                OutlinedButton.icon(
                  onPressed: () => syncManager.cancelSync(),
                  icon: const Icon(Icons.stop, size: 18, color: AppTheme.accentRed),
                  label: const Text('Cancel Fast Transfer', style: TextStyle(color: AppTheme.accentRed)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.accentRed),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => syncManager.startFastTransfer(targetClipId: targetClipId),
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Start WiFi Fast Transfer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhaseRow({
    required int stepNum,
    required String title,
    required String description,
    required bool isActive,
    required bool isDone,
    String? trailingText,
  }) {
    Color iconColor = AppTheme.textMuted;
    Widget leadingWidget;

    if (isDone) {
      iconColor = AppTheme.accentGreen;
      leadingWidget = const Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 20);
    } else if (isActive) {
      iconColor = AppTheme.primaryCyan;
      leadingWidget = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.primaryCyan),
      );
    } else {
      leadingWidget = Icon(Icons.radio_button_unchecked, color: iconColor.withAlpha(120), size: 18);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.primaryCyan.withAlpha(20) : const Color(0xFF1A2333),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? AppTheme.primaryCyan : (isDone ? AppTheme.accentGreen.withAlpha(80) : const Color(0xFF243248)),
          width: isActive ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        children: [
          leadingWidget,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppTheme.primaryCyan : (isDone ? Colors.white : AppTheme.textMuted),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (trailingText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trailingText,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryCyan,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
