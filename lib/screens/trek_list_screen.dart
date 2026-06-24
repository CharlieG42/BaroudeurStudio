import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/trek.dart';
import 'trek_form_screen.dart';
import 'trek_detail_screen.dart';

class TrekListScreen extends StatefulWidget {
  const TrekListScreen({super.key});

  @override
  State<TrekListScreen> createState() => _TrekListScreenState();
}

class _TrekListScreenState extends State<TrekListScreen> {
  List<Trek> _treks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTreks();
  }

  Future<void> _loadTreks() async {
    setState(() => _loading = true);
    final treks = await DatabaseHelper.instance.getTreks();
    setState(() {
      _treks = treks;
      _loading = false;
    });
  }

  String _formatDateRange(Trek trek) {
    try {
      final debut = DateTime.parse(trek.dateDebut);
      final fin = DateTime.parse(trek.dateFin);
      final fmt = DateFormat('dd/MM/yyyy');
      return '${fmt.format(debut)} → ${fmt.format(fin)}';
    } catch (_) {
      return '${trek.dateDebut} → ${trek.dateFin}';
    }
  }

  Future<void> _openNewTrek() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TrekFormScreen()),
    );
    if (created == true) {
      _loadTreks();
    }
  }

  Future<void> _openTrekDetail(Trek trek) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TrekDetailScreen(trek: trek)),
    );
    // Recharge au retour, au cas où le trek a été modifié/supprimé
    _loadTreks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Les Baroudeurs'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _treks.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTreks,
                  child: ListView.builder(
                    itemCount: _treks.length,
                    itemBuilder: (context, index) {
                      final trek = _treks[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.terrain),
                          ),
                          title: Text(
                            trek.titre,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${trek.region}, ${trek.pays}\n${_formatDateRange(trek)}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openTrekDetail(trek),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTrek,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau trek'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hiking, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Aucun trek pour le moment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Appuie sur "Nouveau trek" pour commencer à raconter ton aventure.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
