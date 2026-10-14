import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/trip_planner_database.dart';
import '../models/parametres_planification.dart';

/// Fenetre de parametres du module de planification : vitesses moyennes
/// utilisees pour corriger les durees estimees (marche, velo),
/// preferences d'itineraire pour la voiture (autoroutes, peages) et
/// couleur d'affichage du parcours sur la carte.
/// Les valeurs sont persistees dans la base trip_planner et lues a
/// chaque recalcul des trajets.
class ParametresPlanificationScreen extends StatefulWidget {
  const ParametresPlanificationScreen({super.key});

  @override
  State<ParametresPlanificationScreen> createState() =>
      _ParametresPlanificationScreenState();
}

class _ParametresPlanificationScreenState
    extends State<ParametresPlanificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _marcheController = TextEditingController();
  final _veloController = TextEditingController();
  bool _eviterAutoroutes = false;
  bool _eviterPeages = false;
  Color _couleurParcours = ParametresPlanification().couleurParcours;
  bool _chargement = true;

  static const _paletteParcours = [
    Color(0xFF2196F3),
    Color(0xFF1565C0),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFF44336),
    Color(0xFF9C27B0),
    Color(0xFF795548),
    Color(0xFF607D8B),
    Color(0xFF212121),
  ];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _marcheController.dispose();
    _veloController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final p = await TripPlannerDatabase.instance.getParametres();
    if (!mounted) return;
    setState(() {
      _marcheController.text =
          p.vitesseMarcheKmh.toStringAsFixed(1).replaceAll('.', ',');
      _veloController.text =
          p.vitesseVeloKmh.toStringAsFixed(1).replaceAll('.', ',');
      _eviterAutoroutes = p.eviterAutoroutes;
      _eviterPeages = p.eviterPeages;
      _couleurParcours = p.couleurParcours;
      _chargement = false;
    });
  }

  Future<void> _enregistrer() async {
    if (_formKey.currentState?.validate() != true) return;
    final marche = _parseDouble(_marcheController.text);
    final velo = _parseDouble(_veloController.text);
    await TripPlannerDatabase.instance.saveParametres(
      ParametresPlanification(
        vitesseMarcheKmh: marche ?? 4.5,
        vitesseVeloKmh: velo ?? 18.0,
        eviterAutoroutes: _eviterAutoroutes,
        eviterPeages: _eviterPeages,
        couleurParcours: _couleurParcours,
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  /// Accepte '4,5' comme '4.5' (clavier francais).
  double? _parseDouble(String valeur) =>
      double.tryParse(valeur.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return Scaffold(
        appBar: AppBar(title: const Text('Parametres')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parametres de planification'),
        actions: [
          TextButton(
            onPressed: _enregistrer,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Vitesses moyennes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Utilisees pour corriger les durees estimees des trajets '
              'a pied et a velo (les profils de routage supposent un '
              'terrain plat et un rythme soutenu).',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _marcheController,
              decoration: const InputDecoration(
                labelText: 'Vitesse de marche (km/h)',
                helperText: 'Randonnee : 3 a 5 km/h selon le denivele',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9.,]'),
                ),
              ],
              validator: (v) {
                final value = _parseDouble(v ?? '');
                if (value == null || value <= 0 || value > 20) {
                  return 'Entre 0,1 et 20 km/h';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _veloController,
              decoration: const InputDecoration(
                labelText: 'Vitesse a velo (km/h)',
                helperText: 'Cyclotourisme : 15 a 20 km/h, VTT : 10 a 15',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9.,]'),
                ),
              ],
              validator: (v) {
                final value = _parseDouble(v ?? '');
                if (value == null || value <= 0 || value > 60) {
                  return 'Entre 0,1 et 60 km/h';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Itineraires voiture',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Eviter les autoroutes'),
              subtitle: const Text(
                'Prendre les routes secondaires plutot que les autoroutes',
              ),
              value: _eviterAutoroutes,
              onChanged: (v) => setState(() => _eviterAutoroutes = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Eviter les peages'),
              subtitle: const Text(
                'Proscrire les segments a peage quand une alternative existe',
              ),
              value: _eviterPeages,
              onChanged: (v) => setState(() => _eviterPeages = v),
            ),
            const SizedBox(height: 24),
            const Text(
              'Affichage',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Couleur du parcours trace sur la carte.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final couleur in _paletteParcours)
                  _ChoixCouleur(
                    couleur: couleur,
                    selectionnee:
                        couleur.toARGB32() == _couleurParcours.toARGB32(),
                    onTap: () => setState(() => _couleurParcours = couleur),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Les preferences s'appliquent au prochain recalcul des "
              'trajets (bouton "Recalculer les trajets").',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastille cliquable de la palette de couleurs du parcours.
class _ChoixCouleur extends StatelessWidget {
  const _ChoixCouleur({
    required this.couleur,
    required this.selectionnee,
    required this.onTap,
  });

  final Color couleur;
  final bool selectionnee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: couleur,
          shape: BoxShape.circle,
          border: Border.all(
            color: selectionnee
                ? Theme.of(context).colorScheme.onSurface
                : Colors.black26,
            width: selectionnee ? 3 : 1,
          ),
        ),
        child: selectionnee
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}
