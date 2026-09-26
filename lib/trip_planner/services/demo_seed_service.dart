import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import '../models/voyage.dart';
import 'trip_calculation_service.dart';

/// Pre-remplit un voyage de demonstration a partir de l'itineraire USA
/// decrit par l'utilisateur (Las Vegas -> Grand Canyon -> Monument
/// Valley -> Page -> Bryce Canyon -> Zion -> Las Vegas -> San
/// Francisco), pour valider immediatement le module avec des donnees
/// reelles. Les dates sont indicatives (a partir du 3 octobre) : elles
/// sont a ajuster dans l'app une fois les vols reserves.
class DemoSeedService {
  Future<int> creerVoyageDemoUsa() async {
    final db = TripPlannerDatabase.instance;

    final voyageId = await db.insertVoyage(Voyage(
      titre: 'USA - Grand Circle & San Francisco',
      dateDebut: '2026-10-03',
      dateFin: '2026-10-17',
      notes: 'Road trip familial au depart de Lyon. Trajets en voiture de '
          'Las Vegas au Grand Circle, puis vol Las Vegas -> San Francisco.',
    ));

    final etapes = <Etape>[
      Etape(
        voyageId: voyageId,
        ordre: 0,
        nom: 'Las Vegas, NV',
        latitude: 36.1699,
        longitude: -115.1398,
        date: '2026-10-03',
        type: TypeEtape.visite,
        notes: 'Arrivee, quelques jours sur place avant le road trip.',
        heureArrivee: '14:00',
        dateDepart: '2026-10-05',
        heureDepart: '09:00',
      ),
      Etape(
        voyageId: voyageId,
        ordre: 1,
        nom: 'Grand Canyon National Park (South Rim)',
        latitude: 36.0544,
        longitude: -112.1401,
        date: '2026-10-06',
        type: TypeEtape.visite,
        dureeVisiteMinutes: 60 * 6,
      ),
      Etape(
        voyageId: voyageId,
        ordre: 2,
        nom: 'Monument Valley',
        latitude: 36.9989,
        longitude: -110.0987,
        date: '2026-10-07',
        type: TypeEtape.visite,
        dureeVisiteMinutes: 60 * 4,
      ),
      Etape(
        voyageId: voyageId,
        ordre: 3,
        nom: 'Page, AZ',
        latitude: 36.9147,
        longitude: -111.4558,
        date: '2026-10-08',
        type: TypeEtape.visite,
        notes: 'Penser a reserver le creneau Antelope Canyon a l\'avance.',
        dureeVisiteMinutes: 60 * 6,
      ),
      Etape(
        voyageId: voyageId,
        ordre: 4,
        nom: 'Bryce Canyon National Park',
        latitude: 37.5930,
        longitude: -112.1871,
        date: '2026-10-09',
        type: TypeEtape.visite,
        notes: 'Altitude ~2400 m : nuits fraiches en octobre.',
        dureeVisiteMinutes: 60 * 5,
      ),
      Etape(
        voyageId: voyageId,
        ordre: 5,
        nom: 'Zion National Park',
        latitude: 37.2982,
        longitude: -112.9880,
        date: '2026-10-10',
        type: TypeEtape.visite,
        dureeVisiteMinutes: 60 * 6,
      ),
      Etape(
        voyageId: voyageId,
        ordre: 6,
        nom: 'Las Vegas, NV (retour avant vol)',
        latitude: 36.1699,
        longitude: -115.1398,
        date: '2026-10-11',
        type: TypeEtape.passage,
        notes: 'Retour pour prendre le vol vers San Francisco.',
      ),
      Etape(
        voyageId: voyageId,
        ordre: 7,
        nom: 'San Francisco, CA',
        latitude: 37.7749,
        longitude: -122.4194,
        date: '2026-10-12',
        type: TypeEtape.visite,
        notes: 'Vol Las Vegas -> San Francisco.',
        dureeVisiteMinutes: 60 * 24 * 4,
      ),
    ];

    final ids = <int>[];
    for (final etape in etapes) {
      ids.add(await db.insertEtape(etape));
    }

    // Calcule les trajets routiers (mode voiture) entre etapes
    // consecutives. Le saut Las Vegas -> San Francisco se fait en
    // avion : on le remplace juste apres par un transfert manuel,
    // que le recalcul automatique ne touchera plus ensuite (voir
    // TripCalculationService).
    final calcService = TripCalculationService();
    await calcService.recalculerTrajets(voyageId);

    final lasVegasRetourId = ids[6];
    final sanFranciscoId = ids[7];
    await db.upsertTrajet(Trajet(
      voyageId: voyageId,
      etapeDepartId: lasVegasRetourId,
      etapeArriveeId: sanFranciscoId,
      mode: ModeTransport.avion,
      distanceKm: 0,
      dureeMinutes: 90,
      geometrieJson: '[]',
      transporteur: 'Vol interieur (a completer)',
      lieuDepart: 'Las Vegas (LAS)',
      lieuArrivee: 'San Francisco (SFO)',
      heureDepart: '11:00',
      heureArrivee: '12:30',
      notes: 'Exemple genere automatiquement : remplace par ton vrai vol.',
    ));

    return voyageId;
  }
}
