import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/trek.dart';
import '../models/jour_trek.dart';
import '../widgets/export_odp_button.dart';
import 'trek_form_screen.dart';
import 'jour_form_screen.dart';

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
          ExportOdpButton(trek: _trek),
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
                              subtitle: Text(
                                jour.resume.isEmpty
                                    ? 'Pas de résumé'
                                    : jour.resume,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editJour(jour);
                                  } else if (value == 'delete') {
                                    _deleteJour(jour);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Modifier')),
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
              if (_trek.distanceKm != null)
                Chip(label: Text('${_trek.distanceKm} km')),
              if (_trek.denivelePositifM != null)
                Chip(label: Text('+${_trek.denivelePositifM} m')),
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
