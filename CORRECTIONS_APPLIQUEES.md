

---

## Nettoyage - 29/06/2026

### Suppression de Google Photos Picker
- Raison : API Google Photos Picker v1 a des restrictions majeures
- Solution : Utilisation de file_picker pour selection locale

### Fichiers supprimes
- lib/db/google_photos_picker_service.dart
- lib/config/google_photos_config.dart

### Dependances supprimees
- google_sign_in
- http
- url_launcher

### Alternative active
- file_picker 10.3.10

---

## Etat actuel
- Selection de medias : OK via file_picker
- Stockage local : OK SQLite
- Gestion des treks/jours : OK Complete
- Export PDF : A implementer
