import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Widget d'enregistrement de notes vocales avec transcription automatique
/// via la reconnaissance vocale native du système (Android : moteur Google
/// ou équivalent installé sur l'appareil).
///
/// Le texte transcrit est ajouté au [controller] fourni — l'utilisateur
/// peut ensuite le modifier librement comme n'importe quel champ de texte.
///
/// Note : ce service dépend du moteur de reconnaissance vocale du
/// téléphone, qui nécessite généralement une connexion internet active
/// pour une bonne qualité de transcription (le mode hors-ligne existe
/// mais dépend de packs de langue téléchargés séparément sur l'appareil).
class VoiceNoteRecorder extends StatefulWidget {
  final TextEditingController controller;

  const VoiceNoteRecorder({super.key, required this.controller});

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder> {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _isListening = false;
  String _statusMessage = '';

  @override
  void dispose() {
    if (_isListening) {
      _speech.stop();
    }
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;

    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<void> _startListening() async {
    final hasPermission = await _ensureMicPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permission micro refusée. Active-la dans les paramètres de '
              'l\'app pour utiliser la transcription vocale.',
            ),
          ),
        );
      }
      return;
    }

    _speechAvailable = await _speech.initialize(
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
    );

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
        // On ajoute le texte reconnu au champ existant plutôt que de
        // l'écraser, pour permettre plusieurs sessions d'enregistrement
        // successives sur la même journée.
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          final existing = widget.controller.text;
          final separator = existing.isEmpty ? '' : ' ';
          widget.controller.text = '$existing$separator${result.recognizedWords}';
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
        }
      },
      //SpeechListenOptions.localeId: 'fr_FR',
    );
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
