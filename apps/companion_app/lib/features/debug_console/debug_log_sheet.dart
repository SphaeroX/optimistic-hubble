import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../connection/services/ble_service.dart';

class DebugLogSheet extends StatelessWidget {
  final BleService bleService;

  const DebugLogSheet({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bleService,
      builder: (context, _) {
        final logs = bleService.logs;

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Color(0xFF0A0E17),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(bottom: BorderSide(color: Color(0xFF243248))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.terminal, color: AppTheme.primaryCyan, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Hardware & Protocol Debug Console',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18, color: AppTheme.primaryCyan),
                          tooltip: 'Copy Logs',
                          onPressed: () {
                            final allText = logs.map((l) => '[${l.formattedTime}] [${l.tag}] ${l.message}').join('\n');
                            Clipboard.setData(ClipboardData(text: allText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Logs copied to clipboard')),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Terminal Logs
              Expanded(
                child: logs.isEmpty
                  ? const Center(
                      child: Text('No protocol packets transmitted yet.', style: TextStyle(color: AppTheme.textMuted)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                              children: [
                                TextSpan(
                                  text: '[${log.formattedTime}] ',
                                  style: const TextStyle(color: AppTheme.textMuted),
                                ),
                                TextSpan(
                                  text: '[${log.tag}] ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: log.isError
                                        ? AppTheme.accentRed
                                        : log.tag == 'CMD'
                                            ? AppTheme.accentOrange
                                            : log.tag == 'IMU'
                                                ? AppTheme.accentGreen
                                                : AppTheme.primaryCyan,
                                  ),
                                ),
                                TextSpan(
                                  text: log.message,
                                  style: TextStyle(
                                    color: log.isError ? AppTheme.accentRed : const Color(0xFFD1D5DB),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
