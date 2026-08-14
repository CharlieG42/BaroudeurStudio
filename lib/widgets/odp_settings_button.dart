import 'package:flutter/material.dart';

import '../services/export_service.dart';
import '../services/odp/odp_content_filler.dart';

/// Dialogue de paramétrage de l'export ODP.
///
/// Permet à l'utilisateur d'ajuster les dimensions minimum des images
/// insérées dans le document ODP. Le ratio d'origine est toujours préservé;
/// ces valeurs définissent les seuils minimum (hauteur et largeur) que
/// l'image doit respecter.
///
/// Bouton engrenage à intégrer dans l'AppBar de l'écran de détail du trek.
class OdpSettingsButton extends StatelessWidget {
  const OdpSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Paramétrage de l\'export ODP',
      onPressed: () => _showSettingsDialog(context),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const _OdpSettingsDialog(),
    );
  }
}

class _OdpSettingsDialog extends StatefulWidget {
  const _OdpSettingsDialog();

  @override
  State<_OdpSettingsDialog> createState() => _OdpSettingsDialogState();
}

class _OdpSettingsDialogState extends State<_OdpSettingsDialog> {
  late double _minHeight;
  late double _minWidth;
  late double _maxHeight;
  late double _maxWidth;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await ExportService().getImageSettings();
    if (mounted) {
      setState(() {
        _minHeight = settings.minHeightCm;
        _minWidth = settings.minWidthCm;
        _maxHeight = settings.maxHeightCm;
        _maxWidth = settings.maxWidthCm;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final settings = OdpImageSettings(
      minHeightCm: _minHeight,
      minWidthCm: _minWidth,
      maxHeightCm: _maxHeight,
      maxWidthCm: _maxWidth,
    );
    await ExportService().setImageSettings(settings);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paramètres enregistrés'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _reset() async {
    setState(() {
      _minHeight = OdpImageSettings.defaults.minHeightCm;
      _minWidth = OdpImageSettings.defaults.minWidthCm;
      _maxHeight = OdpImageSettings.defaults.maxHeightCm;
      _maxWidth = OdpImageSettings.defaults.maxWidthCm;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        title: Text('Paramétrage de l\'export ODP'),
        content: Center(child: CircularProgressIndicator()),
      );
    }

    return AlertDialog(
      title: const Text('Paramétrage de l\'export ODP'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dimensions des images',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Le ratio d\'origine est toujours préservé. '
              'Ces valeurs définissent les seuils minimum et maximum '
              'des images insérées dans le document.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Hauteur minimum
            _buildSliderRow(
              label: 'Hauteur minimum',
              value: _minHeight,
              min: 2.0,
              max: 20.0,
              unit: 'cm',
              onChanged: (v) => setState(() => _minHeight = v),
            ),
            const SizedBox(height: 12),

            // Largeur minimum
            _buildSliderRow(
              label: 'Largeur minimum',
              value: _minWidth,
              min: 4.0,
              max: 20.0,
              unit: 'cm',
              onChanged: (v) => setState(() => _minWidth = v),
            ),
            const Divider(height: 24),

            const Text(
              'Limites maximum',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),

            // Hauteur maximum
            _buildSliderRow(
              label: 'Hauteur maximum',
              value: _maxHeight,
              min: 8.0,
              max: 28.0,
              unit: 'cm',
              onChanged: (v) => setState(() => _maxHeight = v),
            ),
            const SizedBox(height: 12),

            // Largeur maximum
            _buildSliderRow(
              label: 'Largeur maximum',
              value: _maxWidth,
              min: 10.0,
              max: 21.0,
              unit: 'cm',
              onChanged: (v) => setState(() => _maxWidth = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('Réinitialiser'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 2).round(),
            label: '${value.toStringAsFixed(1)} $unit',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 55,
          child: Text(
            '${value.toStringAsFixed(1)} $unit',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
