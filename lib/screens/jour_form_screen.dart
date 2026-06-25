import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../db/gpx_service.dart';
import '../models/jour_trek.dart';
import '../widgets/media_gallery.dart';
import '../widgets/voice_note_recorder.dart';

class JourFormScreen extends StatefulWidget {
  final int trekId;
  final JourTrek? jour; // si non-null, mode édition
  final int? suggestedNumero;
  final String? trekDateDebut; // pour suggérer une date par défaut

  const JourFormScreen({
    super.key,
    required this.trekId,
    this.jour,
    this.suggestedNumero,
    this.trekDateDebut,
  });

  @override
  State<JourFormScreen> createState() => _JourFormScreenState();
}

class _JourFormScreenState extends State<JourFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _numeroCtrl;
  late TextEditingController _lieuDepartCtrl;
  late TextEditingController _lieuArriveeCtrl;
  late TextEditingController _distanceCtrl;
  late TextEditingController _denivelePositifCtrl;
  late TextEditingController _deniveleNegatifCtrl;
  late TextEditingController _meteoCtrl;
  late TextEditingController _resumeCtrl;
  late TextEditingController _emotionsCtrl;
  late TextEditingController _difficultesCtrl;
  late TextEditingController _decouvertesCtrl;
  late TextEditingController _notesVocalesCtrl;

  DateTime? _date;
  String? _cheminGpx;
  bool _importingGpx = false;

  final _gpxService = GpxService();

  // Une fois le jour sauvegardé au moins une fois, on connaît son ID
  // et on peut afficher la galerie de photos.
  int? _savedJourId;

  bool get _isEditing => widget.jour != null;

  @override
  void initState() {
    super.initState();
    final jour = widget.jour;

    _numeroCtrl = TextEditingController(
      text: jour?.numeroJour.toString() ?? widget.suggestedNumero?.toString() ?? '1',
    );
    _lieuDepartCtrl = TextEditingController(text: jour?.lieuDepart ?? '');
    _lieuArriveeCtrl = TextEditingController(text: jour?.lieuArrivee ?? '');
    _distanceCtrl = TextEditingController(
      text: jour?.distanceKm != null ? jour!.distanceKm.toString() : '',
    );
    _denivelePositifCtrl = TextEditingController(
      text: jour?.denivelePositifM != null ? jour!.denivelePositifM.toString() : '',
    );
    _deniveleNegatifCtrl = TextEditingController(
      text: jour?.deniveleNegatifM != null ? jour!.deniveleNegatifM.toString() : '',
    );
    _meteoCtrl = TextEditingController(text: jour?.meteo ?? '');
    _resumeCtrl = TextEditingController(text: jour?.resume ?? '');
    _emotionsCtrl = TextEditingController(text: jour?.emotions ?? '');
    _difficultesCtrl = TextEditingController(text: jour?.difficultes ?? '');
    _decouvertesCtrl = TextEditingController(text: jour?.decouvertes ?? '');
    _notesVocalesCtrl = TextEditingController(text: jour?.notesVocalesTranscription ?? '');
    _cheminGpx = jour?.cheminGpx;

    if (jour != null) {
      _date = DateTime.tryParse(jour.date);
      _savedJourId = jour.id;
    } else if (widget.trekDateDebut != null) {
      final debut = DateTime.tryParse(widget.trekDateDebut!);
      final numero = widget.suggestedNumero ?? 1;
      if (debut != null) {
        _date = debut.add(Duration(days: numero - 1));
      }
    }
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _lieuDepartCtrl.dispose();
    _lieuArriveeCtrl.dispose();
    _distanceCtrl.dispose();
    _denivelePositifCtrl.dispose();
    _deniveleNegatifCtrl.dispose();
    _meteoCtrl.dispose();
    _resumeCtrl.dispose();
    _emotionsCtrl.dispose();
    _difficultesCtrl.dispose();
    _decouvertesCtrl.dispose();
    _notesVocalesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  /// Ouvre un sélecteur de fichier pour choisir un fichier .gpx, calcule
  /// distance et dénivelé à partir de la trace, et pré-remplit les champs
  /// correspondants (que l'utilisateur peut ensuite modifier librement).
  Future<void> _importerGpx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );

    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    setState(() => _importingGpx = true);

    try {
      final stats = await _gpxService.calculerStats(sourcePath);

      if (stats.nombrePoints < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ce fichier GPX ne contient pas assez de points pour calculer une trace.'),
            ),
          );
        }
        return;
      }

      // Copie le fichier dans le dossier de l'app. Si le jour n'a pas
      // encore été sauvegardé une première fois, on le sauvegarde
      // silencieusement pour obtenir un ID, nécessaire pour organiser
      // le stockage par jour (même logique que pour les photos).
      if (_savedJourId == null) {
        await _save(andClose: false, showSnackbar: false);
      }
      if (_savedJourId == null) return; // la sauvegarde a échoué

      final copiedPath = await _gpxService.copierGpxPourJour(
        jourId: _savedJourId!,
        sourcePath: sourcePath,
      );

      setState(() {
        _cheminGpx = copiedPath;
        _distanceCtrl.text = stats.distanceKm.toStringAsFixed(2);
        _denivelePositifCtrl.text = stats.denivelePositifM.toString();
        _deniveleNegatifCtrl.text = stats.deniveleNegatifM.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Trace importée : ${stats.distanceKm.toStringAsFixed(2)} km, '
              '+${stats.denivelePositifM} m / -${stats.deniveleNegatifM} m. '
              'Tu peux ajuster ces valeurs si besoin.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la lecture du fichier GPX : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importingGpx = false);
    }
  }

  Future<void> _save({bool andClose = true, bool showSnackbar = true}) async {
    if (!_formKey.currentState!.validate()) return;

    final date = _date ?? DateTime.now();

    final jour = JourTrek(
      id: _savedJourId ?? widget.jour?.id,
      trekId: widget.trekId,
      numeroJour: int.tryParse(_numeroCtrl.text.trim()) ?? 1,
      date: DateFormat('yyyy-MM-dd').format(date),
      lieuDepart: _lieuDepartCtrl.text.trim(),
      lieuArrivee: _lieuArriveeCtrl.text.trim(),
      distanceKm: _distanceCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_distanceCtrl.text.trim().replaceAll(',', '.')),
      meteo: _meteoCtrl.text.trim(),
      resume: _resumeCtrl.text.trim(),
      emotions: _emotionsCtrl.text.trim(),
      difficultes: _difficultesCtrl.text.trim(),
      decouvertes: _decouvertesCtrl.text.trim(),
      denivelePositifM: _denivelePositifCtrl.text.trim().isEmpty
          ? null
          : int.tryParse(_denivelePositifCtrl.text.trim()),
      deniveleNegatifM: _deniveleNegatifCtrl.text.trim().isEmpty
          ? null
          : int.tryParse(_deniveleNegatifCtrl.text.trim()),
      notesVocalesTranscription: _notesVocalesCtrl.text.trim(),
      cheminGpx: _cheminGpx,
    );

    if (_savedJourId != null || _isEditing) {
      await DatabaseHelper.instance.updateJour(jour);
    } else {
      final newId = await DatabaseHelper.instance.insertJour(jour);
      setState(() => _savedJourId = newId);
    }

    if (!mounted) return;

    if (andClose) {
      Navigator.pop(context, true);
    } else if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jour enregistré.'), duration: Duration(seconds: 1)),
      );
    }
  }

  String _displayDate(DateTime? date) {
    if (date == null) return 'Sélectionner une date';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Si on a déjà sauvegardé au moins une fois (ou modifié un jour existant),
        // on signale au parent qu'il y a eu un changement.
        Navigator.pop(context, _savedJourId != null || _isEditing);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing || _savedJourId != null ? 'Modifier le jour' : 'Nouveau jour'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _savedJourId != null || _isEditing),
              child: const Text('Fermer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _numeroCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Jour n°',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Requis';
                      if (int.tryParse(value.trim()) == null) return 'Doit être un nombre';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_displayDate(_date)),
                    onPressed: _pickDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lieuDepartCtrl,
              decoration: const InputDecoration(
                labelText: 'Lieu de départ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lieuArriveeCtrl,
              decoration: const InputDecoration(
                labelText: 'Lieu d\'arrivée',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _distanceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Distance (km)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _meteoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Météo',
                      hintText: 'ex: Grand beau, orage...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _importingGpx ? null : _importerGpx,
              icon: _importingGpx
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.route),
              label: Text(
                _cheminGpx != null
                    ? 'Trace GPX importée — réimporter'
                    : 'Importer une trace GPX',
              ),
            ),
            if (_cheminGpx != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Distance et dénivelé pré-remplis depuis la trace — modifiables ci-dessous.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _denivelePositifCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dénivelé + (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _deniveleNegatifCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dénivelé - (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _resumeCtrl,
              decoration: const InputDecoration(
                labelText: 'Résumé de la journée',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emotionsCtrl,
              decoration: const InputDecoration(
                labelText: 'Émotions',
                hintText: 'ex: Fatigue, émerveillement, fierté...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _difficultesCtrl,
              decoration: const InputDecoration(
                labelText: 'Difficultés',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _decouvertesCtrl,
              decoration: const InputDecoration(
                labelText: 'Découvertes',
                hintText: 'ex: Animaux croisés, lieux remarquables...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            const Text(
              'Notes vocales',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            VoiceNoteRecorder(controller: _notesVocalesCtrl),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesVocalesCtrl,
              decoration: const InputDecoration(
                labelText: 'Transcription (modifiable)',
                hintText: 'Le texte transcrit apparaît ici, et peut être corrigé librement.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _save(andClose: false),
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            if (_savedJourId != null)
              MediaGallery(jourId: _savedJourId!)
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enregistre ce jour une première fois pour pouvoir y ajouter des photos.',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      ),
    );
  }
}
