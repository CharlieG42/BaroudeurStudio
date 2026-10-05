# Module "Préparation de trek" (checklist de matériel)

Nouveau module ajouté à BaroudeurStudio, **totalement indépendant** du
carnet de trek et du planificateur de voyage : fichier SQLite séparé
(`trek_preparation.db`), aucune table partagée. Il permet de composer
des listes de matériel à emporter pour un trek, à partir d'un
catalogue de matériel réutilisable, avec comptabilisation du poids par
catégorie et du poids total.

## Comment l'essayer

1. Lancer l'app, appuyer sur l'icône sac à dos 🎒 dans la barre du haut
   de l'écran d'accueil.
2. Écran "Préparation de trek" : créer une liste (nom + date du trek
   optionnelle).
3. Depuis la liste, bouton "Ajouter du matériel" : le catalogue s'ouvre
   en mode sélection. Si le catalogue est vide, créer d'abord du
   matériel avec l'icône panier (catalogue) puis le bouton
   "Nouveau matériel".
4. Le détail de la liste affiche le **poids total** et le **poids par
   famille** (catégorie), mis à jour à chaque ajout/retrait/quantité.

## Le matériel

Chaque matériel du catalogue possède :

- un **nom**
- une **marque** (liste personnalisable, créable directement depuis le
  formulaire)
- une **description**
- un **poids** (en grammes)
- une **famille** (liste personnalisable)
- une **sous-famille** (liste personnalisable, rattachée à une famille)
- une **photo** (copiée dans le dossier `trek_preparation_photos` du
  dossier Documents de l'app)

Les familles, sous-familles et marques sont personnalisables par
l'utilisateur via l'icône catégorie du catalogue (onglets Familles /
Sous-familles / Marques). Quelques familles de départ sont proposées
(Vêtement, Sac à dos, Couchage, Cuisine, Hygiène, Électronique,
Divers) ; elles sont modifiables ou supprimables.

## Comptabilisation du poids

- Chaque ligne d'une liste a une **quantité** (+/-) et une case
  **"pris"** pour cocher le matériel au moment du remplissage du sac.
- Le poids de la liste est calculé côté SQL :
  `SUM(poids_grammes x quantite)`, globalement (**poids total**) et
  groupé par famille (**poids par catégorie**), affichés en tête du
  détail de la liste.

## Structure

Tout le module est dans `lib/trek_preparation/` :

```
lib/trek_preparation/
  models/       Famille, SousFamille, Marque, Materiel, ListeMateriel,
                LigneListe (+ LigneListeDetaillee, PoidsParFamille)
  db/           TrekPreparationDatabase (SQLite séparé : trek_preparation.db)
  services/     MaterielPhotoStorageService (copie/suppression des photos),
                PreparationExportService (import/export .bwzt)
  screens/      ListeMaterielListScreen (accueil du module),
                ListeMaterielFormScreen, ListeMaterielDetailScreen,
                MaterielListScreen (catalogue, aussi en mode sélection),
                MaterielFormScreen,
                FamillesMarquesManagementScreen
```

## Ce qui a été modifié dans le code existant

- `lib/screens/trek_list_screen.dart` : ajout d'une icône dans l'AppBar
  pour ouvrir le nouveau module. C'est la seule modification du code
  existant.

## Import / export (.bwzt)

L'écran d'accueil du module propose deux icônes supplémentaires :

- **Importer** (flèche upload) : ouvre un fichier `.bwzt` et intègre le
  catalogue (familles, sous-familles, marques, matériels avec photos)
  puis crée les listes de préparation contenues dans l'archive.
- **Exporter** (icône partage) : génère un fichier `preparation_trek.bwzt`
  contenant tout le module (catalogue + listes), à partager sur mobile ou
  à enregistrer via une boîte de dialogue sur Windows.

Le `.bwzt` est une archive ZIP standard (renommer en `.zip` pour
l'inspecter) contenant `preparation.json` et le dossier `photos/`. À
l'import, familles/sous-familles/marques sont dédupliquées par nom, les
matériels existants (même nom + même marque) sont réutilisés, et les
listes sont toujours créées en nouvelles.

Aucune nouvelle dépendance : le module réutilise `sqflite`,
`sqflite_common_ffi`, `path_provider`, `path`, `uuid` et `file_picker`
déjà présents dans `pubspec.yaml`.
