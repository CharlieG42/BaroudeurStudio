import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/trek.dart';
import '../models/jour_trek.dart';
import '../models/totaux_trek.dart';
import '../services/trek_export_service.dart';
import '../widgets/export_odp_button.dart';
import '../widgets/odp_settings_button.dart';
import 'trek_form_screen.dart';
import 'jour_form_screen.dart';
import 'jour_trace_screen.dart';

class TrekDetailScreen extends StatefulWidget {
  final Trek trek;

  const TrekDetailScreen({super.key, required this.trek});

  @override
  State<TrekDetailScreen> createState() => _TrekDetailScreenState();
}

class _TrekDetailScreenState extends State<TrekDetailScreen> {
  late Trek _trek;
  List<JourTrek> _jours = [];
  bool _loading = true;
  final TrekExportService _exportService = TrekExportService();

  @override
  void initState() {
    super.initState();
    _trek = widget.trek;
    _loadJours();
  }

  Future<void> _loadJours() async {
    setState(() => _loading = true);
    final jours = await DatabaseHelper.instance.getJoursForTrek(_trek.id!);
    setState(() {
      _jours = jours;
      _loading = false;
    });
  }

  Future<void> _editTrek() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TrekFormScreen(trek: _trek)),
    );
    if (updated == true) {
      final refreshed = await DatabaseHelper.instance.getTrek(_trek.id!);
      if (refreshed != null && mounted) {
        setState(() => _trek = refreshed);
      }
    }
  }

  Future<void> _deleteTrek() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce trek ?'),
        content: Text(
          'Le trek "${_trek.titre}" et tous ses jours seront définitivement supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteTrek(_trek.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _addJour() async {
    final nextNumero = _jours.isEmpty
        ? 1
        : (_jours.map((j) => j.numeroJour).reduce((a, b) => a > b ? a : b) + 1);

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JourFormScreen(
          trekId: _trek.id!,
          suggestedNumero: nextNumero,
          trekDateDebut: DateFormat('yyyy-MM-dd').format(DateTime.parse(_trek.dateDebut)),
        ),
      ),
    );
    if (created == true) {
      _loadJours();
    }
  }

  Future<void> _editJour(JourTrek jour) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JourFormScreen(
          trekId: _trek.id!,
          jour: jour,
          trekDateDebut: DateFormat('yyyy-MM-dd').format(DateTime.parse(_trek.dateDebut)),
        ),
      ),
    );
    if (updated == true) {
      _loadJours();
    }
  }

  Future<void> _deleteJour(JourTrek jour) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer le Jour ${jour.numeroJour} ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteJour(jour.id!);
      _loadJours();
    }
  }

  /// Exporte le trek en .bwzt puis propose de le partager (mobile)
  /// ou de choisir l'emplacement d'enregistrement (Windows).
  Future<void> _exporterTrek() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text("Préparation de l'export...")),
    );
    try {
      final fichier = await _exportService.exporterTrek(_trek);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer le trek',
          fileName: fichier.path.split(Platform.pathSeparator).last,
          bytes: await fichier.readAsBytes(),
          allowedExtensions: ['bwzt'],
        );
        if (savePath != null) {
          await File(savePath).writeAsBytes(await fichier.readAsBytes());
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trek exporté.')),
          );
        }
      } else {
        await Share.shareXFiles(
          [XFile(fichier.path)],
          subject: 'Trek : ${_trek.titre}',
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Échec de l'export : $e")),
      );
    }
  }

  String _formatDateRange() {
    final fmt = DateFormat('dd/MM/yyyy');
    return '${fmt.format(DateTime.parse(_trek.dateDebut))} → ${fmt.format(DateTime.parse(_trek.dateFin))}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_trek.titre),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exporter (.bwzt)',
            onPressed: _exporterTrek,
          ),
          ExportOdpButton(trek: _trek),
          const OdpSettingsButton(),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Modifier le trek',
            onPressed: _editTrek,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Supprimer le trek',
            onPressed: _deleteTrek,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryCard(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text(
                  'Journal quotidien',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('${_jours.length} jour(s)', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _jours.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun jour renseigné.\nAppuie sur "Ajouter un jour" pour commencer.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _jours.length,
                        itemBuilder: (context, index) {
                          final jour = _jours[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text('${jour.numeroJour}'),
                              ),
                              title: Text(
                                jour.lieuDepart.isEmpty && jour.lieuArrivee.isEmpty
                                    ? 'Jour ${jour.numeroJour}'
                                    : '${jour.lieuDepart} → ${jour.lieuArrivee}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: _buildJourSubtitle(jour),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editJour(jour);
                                  } else if (value == 'trace') {
                                    _voirTrace(jour);
                                  } else if (value == 'delete') {
                                    _deleteJour(jour);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                                  if (jour.cheminGpx != null &&
                                      jour.cheminGpx!.isNotEmpty)
                                    const PopupMenuItem(
                                      value: 'trace',
                                      child: Text('Voir la trace'),
                                    ),
                                  const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                                ],
                              ),
                              onTap: () => _editJour(jour),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addJour,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un jour'),
      ),
    );
  }

  void _voirTrace(JourTrek jour) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JourTraceScreen(
          cheminGpx: jour.cheminGpx!,
          titre: 'Trace du jour ${jour.numeroJour}',
        ),
      ),
    );
  }

  /// Ligne de statistiques du jour (distance, denivelés, trace GPX)
  /// suivie du resume.
  Widget _buildJourSubtitle(JourTrek jour) {
    final stats = <String>[
      if (jour.distanceKm != null) formaterDistanceKm(jour.distanceKm!),
      if (jour.denivelePositifM != null) '+${jour.denivelePositifM} m',
      if (jour.deniveleNegatifM != null) '-${jour.deniveleNegatifM} m',
    ];
    final aGpx = jour.cheminGpx != null && jour.cheminGpx!.isNotEmpty;
    final resume = Text(
      jour.resume.isEmpty ? 'Pas de résumé' : jour.resume,
      maxLines: stats.isEmpty && !aGpx ? 2 : 1,
      overflow: TextOverflow.ellipsis,
    );
    if (stats.isEmpty && !aGpx) return resume;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (aGpx) ...[
              const Icon(Icons.route, size: 14),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                stats.isEmpty ? 'Trace GPX' : stats.join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        resume,
      ],
    );
  }

  /// Distance et denivelés du trek : la valeur saisie dans la fiche du
  /// trek si elle existe, sinon la somme des jours (marquee d'une
  /// icone "somme" pour la distinguer d'une saisie manuelle).
  List<Widget> _buildTotauxChips() {
    final totaux = TotauxTrek.depuisJours(_jours);
    final chips = <Widget>[];

    Widget chip(String texte, {required bool auto}) {
      final c = Chip(
        avatar: auto ? const Icon(Icons.functions, size: 16) : null,
        label: Text(texte),
      );
      return auto
          ? Tooltip(message: 'Calculé depuis les jours', child: c)
          : c;
    }

    if (_trek.distanceKm != null) {
      chips.add(chip(formaterDistanceKm(_trek.distanceKm!), auto: false));
    } else if (totaux.distanceKm != null) {
      chips.add(chip(formaterDistanceKm(totaux.distanceKm!), auto: true));
    }

    if (_trek.denivelePositifM != null) {
      chips.add(chip('+${_trek.denivelePositifM} m', auto: false));
    } else if (totaux.denivelePositifM != null) {
      chips.add(chip('+${totaux.denivelePositifM} m', auto: true));
    }

    // Le denivelé negatif n'existe qu'au niveau des jours.
    if (totaux.deniveleNegatifM != null) {
      chips.add(chip('-${totaux.deniveleNegatifM} m', auto: true));
    }
    return chips;
  }

  Widget _buildSummaryCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_trek.region}, ${_trek.pays}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(_formatDateRange(), style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ..._buildTotauxChips(),
              if (_trek.modeVoyage.isNotEmpty)
                Chip(label: Text(_trek.modeVoyage)),
              if (_trek.compagnons.isNotEmpty)
                Chip(label: Text(_trek.compagnons)),
            ],
          ),
        ],
      ),
    );
  }
}
