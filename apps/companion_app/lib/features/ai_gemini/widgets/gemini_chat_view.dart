import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../recordings/models/dictula_recording.dart';
import '../../recordings/services/recordings_repository.dart';
import '../services/gemini_service.dart';

/// Interactive Chat widget allowing conversation with the Gemini AI about a recording and its transcription.
class GeminiChatView extends StatefulWidget {
  final DictulaRecording recording;
  final String? groupName;
  final GeminiService geminiService;
  final RecordingsRepository repository;

  const GeminiChatView({
    super.key,
    required this.recording,
    this.groupName,
    required this.geminiService,
    required this.repository,
  });

  @override
  State<GeminiChatView> createState() => _GeminiChatViewState();
}

class _GeminiChatViewState extends State<GeminiChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (!widget.geminiService.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst einen Gemini API-Key in den Einstellungen hinterlegen.')),
      );
      return;
    }

    _textController.clear();
    final userMsg = GeminiChatMessage(
      role: 'user',
      text: text,
      timestamp: DateTime.now(),
    );

    await widget.repository.addChatMessage(widget.recording.id, userMsg);
    setState(() => _isLoading = true);
    _scrollToBottom();

    try {
      final answer = await widget.geminiService.sendRecordingChatMessage(
        recordingTitle: widget.recording.title,
        transcription: widget.recording.transcription,
        groupName: widget.groupName,
        history: widget.recording.chatHistory,
        userMessage: text,
      );

      final modelMsg = GeminiChatMessage(
        role: 'model',
        text: answer,
        timestamp: DateTime.now(),
      );
      await widget.repository.addChatMessage(widget.recording.id, modelMsg);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei KI-Anfrage: $e'), backgroundColor: AppTheme.accentRed),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.recording.chatHistory;

    return Column(
      children: [
        // Messages List
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 40, color: AppTheme.primaryCyan.withAlpha(120)),
                        const SizedBox(height: 12),
                        const Text(
                          'KI-Chat mit deiner Sprachaufnahme',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Stelle Fragen zum Inhalt, lasse dir Aufgaben zusammenfassen oder Kernaussagen extrahieren.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final msg = history[index];
                    final isUser = msg.role == 'user';

                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.82,
                        ),
                        decoration: BoxDecoration(
                          color: isUser ? AppTheme.primaryCyan.withAlpha(35) : const Color(0xFF1B273A),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: isUser ? const Radius.circular(14) : const Radius.circular(2),
                            bottomRight: isUser ? const Radius.circular(2) : const Radius.circular(14),
                          ),
                          border: Border.all(
                            color: isUser ? AppTheme.primaryCyan.withAlpha(120) : const Color(0xFF2C3E56),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isUser ? Icons.person : Icons.auto_awesome,
                                  size: 12,
                                  color: isUser ? AppTheme.primaryCyan : AppTheme.accentGreen,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isUser ? 'Du' : 'Gemini KI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isUser ? AppTheme.primaryCyan : AppTheme.accentGreen,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              msg.text,
                              style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                ),
                SizedBox(width: 8),
                Text('Gemini analysiert die Sprachaufnahme...', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),

        // Input Field Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF131C2B),
            border: Border(top: BorderSide(color: Color(0xFF24344B))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    hintText: 'Frage zur Aufnahme stellen...',
                    hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      borderSide: BorderSide(color: Color(0xFF2E405A)),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: AppTheme.primaryCyan),
                onPressed: _isLoading ? null : _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
