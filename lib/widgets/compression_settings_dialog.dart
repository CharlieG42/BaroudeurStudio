import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';

/// Dialogue pour configurer la qualité de compression des images
class CompressionSettingsDialog extends StatefulWidget {
  const CompressionSettingsDialog({super.key});

  @override
  State<CompressionSettingsDialog> createState() => _CompressionSettingsDialogState();
}

class _CompressionSettingsDialogState extends State<CompressionSettingsDialog> {
  late int _currentQuality;

  @override
  void initState() {
    super.initState();
    _currentQuality = AppConfig.imageCompressionQuality;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paramètres de compression'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Qualité de compression des images:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Valeur recommandée: 70-80%',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Text(
            'Qualité actuelle: $_currentQuality%',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Slider(
            value: _currentQuality.toDouble(),
            min: 0,
            max: 100,
            divisions: 10,
            label: '$_currentQuality%',
            onChanged: (value) {
              setState(() {
                _currentQuality = value.toInt();
              });
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildQualityLabel('Faible', 0, Colors.red),
              _buildQualityLabel('Moyenne', 50, Colors.orange),
              _buildQualityLabel('Élevée', 100, Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Conseils:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            '• 50%: Très compressé, fichiers petits',
            style: TextStyle(fontSize: 12),
          ),
          const Text(
            '• 70%: Bon compromis (recommandé)',
            style: TextStyle(fontSize: 12),
          ),
          const Text(
            '• 90%+: Qualité proche de l'original',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            AppConfig.compressionQuality = _currentQuality;
            Navigator.pop(context, _currentQuality);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _buildQualityLabel(String label, int value, Color color) {
    final isSelected = _currentQuality == value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? color : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$value%',
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? color : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

/// Bouton pour ouvrir les paramètres de compression
class CompressionSettingsButton extends StatelessWidget {
  const CompressionSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Paramètres de compression',
      onPressed: () async {
        final newQuality = await showDialog<int>(
          context: context,
          builder: (context) => const CompressionSettingsDialog(),
        );
        
        if (newQuality != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Qualité de compression définie à $newQuality%'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}
