import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../db/media_storage_service.dart';
import '../models/media.dart';

/// Galerie de medias (photos pour l'instant) pour un jour de trek.
/// Permet d'ajouter (via file picker), visualiser en plein ecran,
/// legender, et supprimer des medias.
class MediaGallery extends StatefulWidget {
  final int jourId;

  const MediaGallery({super.key, required this.jourId});

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  final _storageService = MediaStorageService();

  List<Media> _medias = [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _loadMedias();
  }

  Future<void> _loadMedias() async {
    setState(() => _loading = true);
    final medias = await DatabaseHelper.instance.getMediasForJour(widget.jourId);
    setState(() {
      _medias = medias;
      _loading = false;
    });
  }

  /// Demande a l'utilisateur s'il veut importer en taille originale
  /// ou compressee. Retourne true pour compressee, false pour
  /// originale, ou null si l'utilisateur annule l'import.
  Future<bool?> _askCompressionChoice() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Qualite d import'),
        content: const Text(
          'Importer les photos en taille originale, ou compressee '
          '(format reduit, qualite suffisante pour l impression et '
          'l IA, mais beaucoup plus leger sur le disque) ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Taille originale'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Compressee'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final compress = await _askCompressionChoice();
    if (compress == null) return;
    setState(() => _importing = true);
    for (final file in result.files) {
      final sourcePath = file.path;
      if (sourcePath == null) continue;
      try {
        final copiedPath = await _storageService.copyFileForJour(
          jourId: widget.jourId,
          sourcePath: sourcePath,
          compress: compress,
        );
        final media = Media(
          jourId: widget.jourId,
          type: _storageService.detectType(sourcePath),
          cheminFichier: copiedPath,
          nomOriginal: file.name,
          dateAjout: DateTime.now().toIso8601String(),
        );
        await DatabaseHelper.instance.insertMedia(media);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de l import de ${file.name} : $e')),
          );
        }
      }
    }
    setState(() => _importing = false);
    _loadMedias();
  }

  Future<void> _deletePhoto(Media media) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette photo ?'),
        content: Text(media.nomOriginal),
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
      await DatabaseHelper.instance.deleteMedia(media.id!);
      await _storageService.deleteFile(media.cheminFichier);
      _loadMedias();
    }
  }

  Future<void> _editLegende(Media media) async {
    final ctrl = TextEditingController(text: media.legende ?? '');
    final result = await Navigator.push<({String legende, bool couverture})>(
      context,
      MaterialPageRoute(
        builder: (ctx) => _FullScreenLegendeEditor(
          controller: ctrl,
          media: media,
        ),
      ),
    );
    if (result != null && media.id != null) {
      await DatabaseHelper.instance.updateMediaLegende(media.id!, result.legende);
      if (result.couverture != media.estCouverture) {
        if (result.couverture) {
          await DatabaseHelper.instance.setMediaCouverture(media.id!, widget.jourId);
        } else {
          await DatabaseHelper.instance.setMediaCouverture(-1, widget.jourId);
        }
      }
      _loadMedias();
    }
  }

  void _openFullScreen(Media media) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(media.nomOriginal)),
          backgroundColor: Colors.black,
          body: Column(
            children: [
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    child: Image.file(File(media.cheminFichier)),
                  ),
                ),
              ),
              if (media.legende != null && media.legende!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    media.legende!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Photos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            if (_medias.isNotEmpty)
              Text('(${_medias.length})', style: const TextStyle(color: Colors.grey)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _importing ? null : _addPhotos,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate),
              label: Text(_importing ? 'Import...' : 'Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_medias.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Aucune photo pour ce jour.\nClique sur Ajouter pour importer des photos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _medias.length,
            itemBuilder: (context, index) {
              final media = _medias[index];
              return GestureDetector(
                onTap: () => _openFullScreen(media),
                onLongPress: () => _editLegende(media),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(media.cheminFichier),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _deletePhoto(media),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                    if (media.estCouverture)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.star, color: Colors.white, size: 14),
                        ),
                      ),
                    if (media.legende != null && media.legende!.isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                          ),
                          child: Text(
                            media.legende!,
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Editeur de legende en plein ecran avec option "photo de couverture".
class _FullScreenLegendeEditor extends StatefulWidget {
  final TextEditingController controller;
  final Media media;

  const _FullScreenLegendeEditor({
    required this.controller,
    required this.media,
  });

  @override
  State<_FullScreenLegendeEditor> createState() => _FullScreenLegendeEditorState();
}

class _FullScreenLegendeEditorState extends State<_FullScreenLegendeEditor> {
  late bool _estCouverture;

  @override
  void initState() {
    super.initState();
    _estCouverture = widget.media.estCouverture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legende de la photo'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, (
                legende: widget.controller.text.trim(),
                couverture: _estCouverture,
              ));
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Apercu de la photo
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(widget.media.cheminFichier),
              fit: BoxFit.contain,
              height: 250,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 250,
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, size: 64, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Champ legende (grand, multi-lignes)
          TextField(
            controller: widget.controller,
            autofocus: true,
            maxLines: 12,
            expands: false,
            decoration: const InputDecoration(
              labelText: 'Legende',
              hintText: 'Decris cette photo.\nLe texte sera affiche a cote de la photo dans le document ODP.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),

          // Option: photo de couverture du chapitre
          Card(
            child: SwitchListTile(
              title: const Text('Photo de couverture du chapitre'),
              subtitle: const Text(
                'Cette photo sera utilisee sur la page d introduction du jour '
                '(avec le resume). Une seule photo par jour peut etre la couverture.',
              ),
              value: _estCouverture,
              onChanged: (value) {
                setState(() => _estCouverture = value);
              },
              secondary: Icon(
                _estCouverture ? Icons.star : Icons.star_border,
                color: _estCouverture ? Colors.amber : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
