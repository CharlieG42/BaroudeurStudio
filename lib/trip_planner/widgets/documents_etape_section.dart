import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../db/trip_planner_database.dart';
import '../models/document_etape.dart';
import '../services/document_storage_service.dart';

/// Section a inserer dans le formulaire d'etape (uniquement pour une
/// etape deja enregistree, puisqu'il faut son id) : liste des documents
/// attaches (billets, reservations, tickets, photos de justificatifs...)
/// avec ajout, apercu, ouverture et suppression. C'est ce qui transforme
/// le module en un vrai carnet de voyage, au-dela du simple planning.
class DocumentsEtapeSection extends StatefulWidget {
  final int etapeId;

  const DocumentsEtapeSection({super.key, required this.etapeId});

  @override
  State<DocumentsEtapeSection> createState() => _DocumentsEtapeSectionState();
}

class _DocumentsEtapeSectionState extends State<DocumentsEtapeSection> {
  final _storageService = DocumentStorageService();
  List<DocumentEtape> _documents = [];
  bool _loading = true;
  bool _ajoutEnCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _loading = true);
    final documents =
        await TripPlannerDatabase.instance.getDocumentsForEtape(widget.etapeId);
    if (!mounted) return;
    setState(() {
      _documents = documents;
      _loading = false;
    });
  }

  Future<void> _ajouterDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _ajoutEnCours = true);

    for (final file in result.files) {
      final sourcePath = file.path;
      if (sourcePath == null) continue;
      try {
        final cheminCopie = await _storageService.copierFichierPourEtape(
          etapeId: widget.etapeId,
          sourcePath: sourcePath,
        );
        final taille = await _storageService.tailleFichierOctets(cheminCopie);
        await TripPlannerDatabase.instance.insertDocument(DocumentEtape(
          etapeId: widget.etapeId,
          nomOriginal: file.name,
          cheminFichier: cheminCopie,
          tailleOctets: taille,
          dateAjout: DateTime.now().toIso8601String(),
        ));
      } catch (_) {
        if (!mounted) continue;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ajouter "${file.name}".')),
        );
      }
    }

    if (!mounted) return;
    setState(() => _ajoutEnCours = false);
    await _charger();
  }

  Future<void> _ouvrirDocument(DocumentEtape document) async {
    final result = await OpenFile.open(document.cheminFichier);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible d\'ouvrir ce fichier (${result.message}).',
          ),
        ),
      );
    }
  }

  Future<void> _supprimerDocument(DocumentEtape document) async {
    if (document.id == null) return;
    await TripPlannerDatabase.instance.deleteDocument(document.id!);
    await _storageService.supprimerFichier(document.cheminFichier);
    await _charger();
  }

  IconData _iconePourDocument(DocumentEtape document) {
    if (document.estPdf) return Icons.picture_as_pdf_outlined;
    if (document.estImage) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Documents', style: Theme.of(context).textTheme.titleSmall),
            TextButton.icon(
              onPressed: _ajoutEnCours ? null : _ajouterDocuments,
              icon: _ajoutEnCours
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 18),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (_documents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Billets, reservations, tickets d\'entree, photos de '
              'justificatifs... Rien d\'attache pour le moment.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          )
        else
          ...[
            for (final document in _documents)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  onTap: () => _ouvrirDocument(document),
                  leading: document.estImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            File(document.cheminFichier),
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(_iconePourDocument(document)),
                          ),
                        )
                      : Icon(_iconePourDocument(document)),
                  title: Text(
                    document.nomOriginal,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    DocumentStorageService.formaterTaille(
                        document.tailleOctets),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _supprimerDocument(document),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}
