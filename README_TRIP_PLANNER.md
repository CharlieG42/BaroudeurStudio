# Module "Planification de voyage" (TripPlanner)

Nouveau module ajouté à BaroudeurStudio/Les Baroudeurs, **totalement
indépendant** du carnet de trek existant (aucune table SQLite
partagée, aucun fichier existant modifié à part deux petits ajouts
listés plus bas). Il permet de planifier un road trip jour par jour,
avec une carte OpenStreetMap et le calcul automatique des trajets en
voiture entre les étapes.

## Comment l'essayer rapidement

1. `flutter pub get` pour récupérer les 3 nouvelles dépendances
   (`flutter_map`, `latlong2`, `http`).
2. Lancer l'app, appuyer sur l'icône carte 🗺️ dans la barre du haut
   de l'écran d'accueil.
3. Sur l'écran "Planification de voyage" (liste vide au premier
   lancement), bouton **"Charger le voyage USA de démonstration"** :
   ça pré-remplit ton voyage (Las Vegas → Grand Canyon → Monument
   Valley → Page → Bryce Canyon → Zion → Las Vegas → San Francisco)
   avec des coordonnées réelles, pour voir tout de suite la carte et
   les trajets calculés.
4. Depuis la carte, appui long sur un point pour ajouter une étape à
   cet endroit, ou bouton "Ajouter une étape" pour chercher un lieu
   par son nom.

## Ce qui a été modifié dans le code existant

- `pubspec.yaml` : ajout de `flutter_map`, `latlong2`, `http`, `open_file`.
- `lib/screens/trek_list_screen.dart` : ajout d'une icône dans l'AppBar
  pour ouvrir le nouveau module. C'est la seule modification dans le
  code du carnet de trek.

Tout le reste est dans `lib/trip_planner/` :

```
lib/trip_planner/
  models/       Voyage, Etape, Trajet (avec mode de transport), DocumentEtape
  db/           TripPlannerDatabase (fichier SQLite séparé : trip_planner.db)
  services/     OsrmService (routage), NominatimService (recherche de lieu),
                TripCalculationService (recalcule les trajets voiture),
                DocumentStorageService (copie/gestion des fichiers attachés),
                DemoSeedService
  widgets/      DocumentsEtapeSection (liste/ajout/ouverture des documents)
  screens/      VoyageListScreen, VoyageFormScreen, VoyageMapScreen,
                EtapeFormScreen, TransfertFormScreen

Le module waypoints ajoute (même dossier) :
  models/       Waypoint (recommande ou personnel)
  services/     WaypointSuggestionService (POI OpenStreetMap via
                Overpass, autour du trace du voyage)
```

## Fonctionnalités

- **Ma position** : bouton flottant cible sur la carte qui récupère la
  position GPS de l'appareil (demande de permission à la première
  utilisation), l'affiche sous forme d'un point bleu et recentre la
  carte dessus. Position ponctuelle à la demande — pas de suivi
  continu, pour préserver batterie et vie privée.
- **Waypoints recommandés** : bouton étoile dans l'AppBar pour demander
  des suggestions de points d'intérêt autour du tracé du voyage
  (points de vue, cascades, sommets, monuments, attractions...),
  issues des données OpenStreetMap via l'API Overpass. Les
  suggestions sont mises en cache en base et remplacées à chaque
  nouvelle demande ; elles n'affectent ni les trajets ni les dates.
- **Waypoints personnels** : bouton épingle dans l'AppBar pour activer
  le mode « ajout de waypoint » — un simple tap sur la carte pose une
  épingle libre. Chaque waypoint (recommandé ou personnel) affiche une
  fiche au tap avec, notamment, « Convertir en étape » : la conversion
  réutilise la fiche d'étape standard et le recalcul des trajets.
- **Étapes** : point de chute géolocalisé (visite ou simple passage),
  avec date/heure d'arrivée et, pour une visite, date/heure de départ
  optionnelle (utile pour un séjour de plusieurs jours au même endroit).
- **Transferts entre étapes** : par défaut calculés automatiquement en
  voiture (OSRM). Tape sur la ligne entre deux étapes dans la liste
  pour choisir le mode : voiture, vélo ou marche (calculés
  automatiquement, chacun avec son propre itinéraire), ou avion/train/
  bus/autre (saisi manuellement : transporteur, lieux, heures) — ce
  dernier n'est plus jamais écrasé par le recalcul automatique tant
  que les deux étapes restent consécutives.
- **Fonds de carte** : l'icône calques dans l'AppBar bascule entre
  OpenStreetMap, IGN - Plan et IGN - Photos aériennes (service gratuit
  et sans clé de la Géoplateforme, data.geopf.fr). L'IGN ne couvre que
  le territoire français (métropole + outre-mer) : hors de cette zone
  (comme pour ce voyage aux USA), les tuiles resteront vides — garde
  OpenStreetMap pour l'international.
- **Sentiers de randonnée (GR/GRP/PR)** : dans le même menu calques,
  une case à cocher "Sentiers de randonnee" superpose les itinéraires
  de randonnée (GR, GRP, PR, et les hiking trails à l'international)
  sur n'importe quel fond de carte. **Note technique** : la couche
  IGN qui affiche nativement les GR/GRP sur un rendu carte classique
  (l'ancienne "carte IGN classique"/SCAN25, nom technique
  `GEOGRAPHICALGRIDSYSTEMS.MAPS`) fait partie des données à *accès
  restreint* de l'IGN — elle nécessite une clé/un abonnement que
  l'app n'a pas. J'ai donc utilisé à la place le service ouvert et
  sans clé **Waymarked Trails** (tuiles construites à partir des
  données OpenStreetMap, qui incluent les GR/GRP/PR français) : même
  résultat visuel utile, sans dépendance a une cle IGN.
- **Documents attachés** : dans la fiche d'une étape déjà enregistrée,
  section "Documents" pour attacher billets, réservations, tickets
  d'entrée, photos de justificatifs... Stockés localement dans l'app
  (pas de cloud), ouverts avec l'application par défaut du téléphone
  (PDF, image...).

## Choix techniques à connaître

- **Carte** : `flutter_map` avec les tuiles OpenStreetMap standard
  (`tile.openstreetmap.org`). Gratuit, mais à usage raisonnable —
  pour une diffusion large de l'app, il faudra passer par un
  fournisseur de tuiles dédié (MapTiler, Thunderforest, etc.).
- **Calcul d'itinéraire voiture** : API publique OSRM
  (`router.project-osrm.org`), gratuite mais à usage raisonnable
  (max ~1 requête/seconde, pas d'usage commercial intensif). Pour un
  usage plus poussé, héberger sa propre instance OSRM et changer
  `OsrmService.baseUrl`.
- **Recherche de lieu par nom** : API Nominatim
  (`nominatim.openstreetmap.org`), même politique d'usage raisonnable.
- Les trajets sont mis en cache en base (distance, durée, tracé) et
  ne sont recalculés que lorsque tu ajoutes/déplaces/supprimes une
  étape, pour ne pas spammer ces API à chaque ouverture de la carte.
- **Import/export (.bwzt)** : icône en haut de la liste des voyages
  pour importer un fichier `.bwzt` reçu d'un autre appareil ; icône
  de partage sur chaque voyage de la liste pour l'exporter. Un
  `.bwzt` est une archive ZIP standard (JSON + documents attachés
  copiés dedans) — renomme-le en `.zip` pour l'inspecter avec
  n'importe quel outil si besoin. Aucun compte ni service en ligne
  requis : tout reste local tant que le fichier n'est pas transféré
  manuellement (partage, mail, cloud perso...). Dans `voyage.json`,
  les étapes sont repérées par un index local (0, 1, 2...) plutôt que
  par leur id de base de données, ce qui rend le fichier portable
  d'un appareil à l'autre (chaque appareil attribue ses propres id à
  l'import).

## Limites connues de cette version

- Les documents sont stockés uniquement sur l'appareil (pas de
  sauvegarde cloud) : pense à les garder aussi ailleurs pour les
  documents importants (billets d'avion...).
- Pas encore de lien avec le module carnet de trek (ordre du jour
  suggéré ici sera à ressaisir manuellement dans "Les Baroudeurs" une
  fois le voyage terminé, si tu veux en faire un livre).
- Le trace affiché pour un transfert non-voiture (avion/train/bus) est
  une simple ligne droite entre les deux étapes, pas un vrai tracé.
