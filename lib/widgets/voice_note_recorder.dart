import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Widget d'enregistrement de notes vocales avec transcription automatique
/// via la reconnaissance vocale native du système.
/// NOTE: Sur Windows, la reconnaissance vocale est désactivée (pas de support
/// des permissions microphone dans le plugin permission_handler pour VS 2022 18.x)
class VoiceNoteRecorder extends StatefulWidget {
  final TextEditingController controller;

  const VoiceNoteRecorder({super.key, required this.controller});

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder> {
  late final stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    // Initialisation immédiate pour Windows (pas besoin de permission)
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          setState(() {
            _isListening = false;
            _statusMessage = 'Erreur : ${error.errorMsg}';
          });
        },
      ).then((available) => setState(() => _speechAvailable = available));
    }
  }

  @override
  void dispose() {
    if (_isListening) {
      _speech.stop();
    }
    super.dispose();
  }

  Future<void> _startListening() async {
    // Sur Windows, on essaie directement sans vérifier les permissions
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reconnaissance vocale indisponible sur cet appareil.',
              ),
            ),
          );
        }
        return;
      }

      setState(() {
        _isListening = true;
        _statusMessage = 'Écoute en cours... parle maintenant';
      });

      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            final existing = widget.controller.text;
            final separator = existing.isEmpty ? '' : ' ';
            widget.controller.text = '$existing$separator${result.recognizedWords}';
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
          }
        },
      );
      return;
    }

    // Pour Android/iOS: on vérifie les permissions (à implémenter si tu réactives permission_handler)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reconnaissance vocale désactivée sur cette plateforme.',
          ),
        ),
      );
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      _statusMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: _isListening ? _stopListening : _startListening,
              icon: Icon(_isListening ? Icons.stop : Icons.mic),
              label: Text(_isListening ? 'Arrêter' : 'Enregistrer une note vocale'),
              style: FilledButton.styleFrom(
                backgroundColor: _isListening ? Colors.red : null,
              ),
            ),
            if (_isListening)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        if (_statusMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _statusMessage,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }
}