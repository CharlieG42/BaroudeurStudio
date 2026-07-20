# Guide des Bonnes Pratiques - Export ODP (BaroudeurStudio)

> Derniere mise a jour : 20 juillet 2026
> Contributeur : Claude (via CharlieG42)

---

## Contexte
Ce document recense les problemes rencontres, les solutions appliquees, et les bonnes pratiques pour l'export ODP dans BaroudeurStudio.

---

## Problemes Rencontres & Corrections

### Bug n1 : Corruption du texte (Apostrophes et caracteres speciaux)
**Fichier** : lib/services/odp/content_xml_builder.dart (ligne 179)

**Probleme** : La methode _escapeXml utilisait .replaceAll('', '&apos;') qui insere &apos; entre chaque caractere.
**Solution** : Utiliser .replaceAll("'", '&apos;') pour cibler uniquement les apostrophes.
**Impact** : Texte lisible, taille XML normale, plus de problemes memoire.

---

### Bug n2 : Prefixe XML non declare (svg:stroke-color)
**Fichier** : lib/services/odp/styles_xml_builder.dart

**Probleme** : Le style graphic utilisait svg:stroke-color mais la racine office:document-styles ne declarait pas xmlns:svg.
**Solution** : Ajout de xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" dans la balise racine.
**Impact** : XML valide, LibreOffice ouvre le fichier sans erreur.

---

### Bug n3 : Fichier mimetype compresse dans le ZIP
**Fichier** : lib/services/odp/odp_export_service.dart

**Probleme** : Le fichier mimetype etait compresse par defaut, ce qui viole la spec ODF.
**Solution** : mimetypeFile.compress = false; apres creation de l'ArchiveFile.
**Impact** : Archive ZIP conforme au standard ODP.

---

### Bug n4 : Structure XML invalide (draw:text-box sans draw:frame parent)
**Fichier** : lib/services/odp/content_xml_builder.dart

**Probleme** : Les draw:text-box etaient places directement dans draw:page avec des attributs svg:x, svg:y, etc. dessus.
**Solution** : Envelopper tous les draw:text-box dans un draw:frame avec les attributs de position sur le frame.
**Impact** : LibreOffice reconnait les objets graphiques, texte et images s'affichent correctement.

---

## Bonnes Pratiques Generales pour ODP/ODF

### 1. Structure du ZIP ODP
Un fichier ODP est une archive ZIP avec cette structure obligatoire :
- mimetype (PREMIER fichier, NON compresse)
- META-INF/manifest.xml (Liste tous les fichiers de l'archive)
- content.xml (Contenu des slides)
- styles.xml (Styles et mise en page)
- meta.xml (Metadonnees du document)
- Pictures/ (Images embarquees)

### 2. Regles pour mimetype
- Contenu : application/vnd.oasis.opendocument.presentation (pour ODP)
- Position : Premier fichier dans l'archive ZIP
- Compression : Desactivee (compress = false dans archive Dart)

### 3. Namespaces XML Obligatoires
Dans content.xml et styles.xml, tous les prefixes utilises doivent etre declares dans la balise racine.
Exemple pour content.xml :
xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
xmlns:xlink="http://www.w3.org/1999/xlink"
xmlns:dc="http://purl.org/dc/elements/1.1/"
xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"

### 4. Echappement des Caracteres Speciaux
Toujours echapper ces caracteres dans le XML :
- & -> &amp;
- < -> &lt;
- > -> &gt;
- " -> &quot;
- ' -> &apos;

Attention : En Dart, replaceAll('', x) insere x entre chaque caractere (bug n1).

### 5. Structure des Slides en ODF
Chaque slide (draw:page) doit contenir :
- Un ou plusieurs draw:frame (pour positionner le contenu)
- Dans chaque draw:frame :
  - Un draw:text-box pour du texte
  - Ou un draw:image pour une image

---

## Modifications Recentes (20/07/2026)

### Passage en Format Portrait
**Fichier modifie** : lib/services/odp/styles_xml_builder.dart

Avant (Landscape) :
draw:page-width="28cm", draw:page-height="21cm", draw:print-orientation="landscape"

Apres (Portrait) :
draw:page-width="21cm", draw:page-height="28cm", draw:print-orientation="portrait"

Impact : Les slides s'affichent maintenant en format vertical (21cm x 28cm).

---

## Ressources Utiles
- Specification ODF 1.3 (OASIS) : Standard officiel du format ODP
- Package archive (Dart) : Documentation pour la creation d'archives ZIP en Dart
- LibreOffice Impress : Logiciel de reference pour tester les fichiers ODP

---

## Outils de Diagnostic

### Verifier la validite d'un ODP
1. Renommer .odp en .zip et extraire le contenu
2. Verifier :
   - mimetype est le premier fichier dans le ZIP
   - mimetype n'est pas compresse (taille dans le ZIP = taille reelle du fichier)
   - Tous les fichiers declares dans META-INF/manifest.xml existent
   - Le XML est bien forme

### Tester avec LibreOffice
- Ouvrir le fichier ODP avec LibreOffice Impress
- Si le fichier s'ouvre sans erreur et que le contenu s'affiche correctement -> succes

---

## Checklist avant Commit
- [ ] Le fichier mimetype est non compresse et premier dans le ZIP
- [ ] Tous les namespaces XML sont declares dans les balises racines
- [ ] Les caracteres speciaux sont correctement echappes
- [ ] Les draw:text-box sont enfants de draw:frame
- [ ] Le fichier s'ouvre sans erreur dans LibreOffice Impress
- [ ] Le texte et les images s'affichent correctement

---

## Historique des Modifications

| Date | Auteur | Modification | Commit |
|------|--------|--------------|--------|
| 20/07/2026 | Claude (via CharlieG42) | Correction des 4 bugs majeurs | 51814e8 |
| 20/07/2026 | CharlieG42 | Passage en format portrait | b58f5c5 |

---

## Prochaines Etapes
- Tester l'export ODP avec plusieurs treks pour valider la stabilite
- Ajouter des tests unitaires pour la generation XML
- Automatiser la validation des fichiers ODP generes
