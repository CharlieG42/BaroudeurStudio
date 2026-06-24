import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/database_helper.dart';
import '../db/google_photos_picker_service.dart';
import '../db/media_storage_service.dart';
import '../models/media.dart';

/// Galerie de médias (photos pour l'instant) pour un jour de trek.
/// Permet d'ajouter (via file picker), visualiser en plein écran,
/// légender, et supprimer des médias.
class MediaGallery extends StatefulWidget {
  final int jourId;

  const MediaGallery({super.key, required this.jourId});

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  final _storageService = MediaStorageService();
  final _googlePhotosService = GooglePhotosPickerService();

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

  /// Demande à l'utilisateur s'il veut importer en taille originale
  /// ou compressée. Retourne true pour "compressée", false pour
  /// "originale", ou null si l'utilisateur annule l'import.
  Future<bool?> _askCompressionChoice() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Qualité d\'import'),
        content: const Text(
          'Importer les photos en taille originale, ou compressées '
          '(format réduit, qualité suffisante pour l\'impression et '
          'l\'IA, mais beaucoup plus léger sur le disque) ?',
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
            child: const Text('Compressée'),
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
    if (compress == null) return; // utilisateur a annulé

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
            SnackBar(content: Text('Erreur lors de l\'import de ${file.name} : $e')),
          );
        }
      }
    }

    setState(() => _importing = false);
    _loadMedias();
  }

  /// Lance le flux Google Photos Picker : ouvre le sélecteur dans le
  /// navigateur, attend la sélection, télécharge chaque média choisi
  /// vers un fichier temporaire, puis le fait passer par le service de
  /// stockage habituel (avec le même choix taille originale/compressée).
  Future<void> _importFromGooglePhotos() async {
    final compress = await _askCompressionChoice();
    if (compress == null) return; // utilisateur a annulé

    setState(() => _importing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      String? accessTokenForDownload;

      final pickedMedia = await _googlePhotosService.pickMedia(
        onPickerReady: (pickerUri) async {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Sélectionne tes photos dans Google Photos, puis reviens '
                  'dans l\'app — l\'import continuera automatiquement.',
                ),
                duration: Duration(seconds: 6),
              ),
            );
          }
          final uri = Uri.parse(pickerUri);
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!launched) {
            throw Exception('Impossible d\'ouvrir le sélecteur Google Photos.');
          }
        },
      );

      if (pickedMedia.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucune photo sélectionnée.')),
          );
        }
        return;
      }

      // On récupère un token une seule fois pour télécharger tous les
      // fichiers sélectionnés (évite de re-déclencher l'auth à chaque
      // photo).
      accessTokenForDownload = await _googlePhotosService.getCurrentAccessToken();

      for (final media in pickedMedia) {
        try {
          final bytes = await _googlePhotosService.downloadMediaBytes(
            media,
            accessToken: accessTokenForDownload,
          );

          // Écrit les octets téléchargés dans un fichier temporaire, pour
          // pouvoir réutiliser le service de stockage existant (qui
          // attend un chemin de fichier source, pas des octets bruts).
          final tempPath = p.join(tempDir.path, media.filename);
          final tempFile = File(tempPath);
          await tempFile.writeAsBytes(bytes);

          final copiedPath = await _storageService.copyFileForJour(
            jourId: widget.jourId,
            sourcePath: tempPath,
            compress: compress,
          );

          final newMedia = Media(
            jourId: widget.jourId,
            type: _storageService.detectType(tempPath),
            cheminFichier: copiedPath,
            nomOriginal: media.filename,
            dateAjout: DateTime.now().toIso8601String(),
          );

          await DatabaseHelper.instance.insertMedia(newMedia);

          // Nettoyage du fichier temporaire (best-effort).
          try {
            await tempFile.delete();
          } catch (_) {}
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors de l\'import de ${media.filename} : $e')),
            );
          }
        }
      }
    } on PickerCancelledException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur Google Photos : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
      _loadMedias();
    }
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
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Légende de la photo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'ex: Vue depuis le col, marmotte croisée...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (result != null && media.id != null) {
      await DatabaseHelper.instance.updateMediaLegende(media.id!, result);
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
            PopupMenuButton<String>(
              enabled: !_importing,
              onSelected: (value) {
                if (value == 'files') {
                  _addPhotos();
                } else if (value == 'google_photos') {
                  _importFromGooglePhotos();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'files',
                  child: Row(
                    children: [
                      Icon(Icons.folder_open),
                      SizedBox(width: 8),
                      Text('Depuis l\'appareil'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'google_photos',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_download),
                      SizedBox(width: 8),
                      Text('Depuis Google Photos'),
                    ],
                  ),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate),
                  const SizedBox(width: 6),
                  Text(_importing ? 'Import...' : 'Ajouter'),
                ],
              ),
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
                'Aucune photo pour ce jour.\nClique sur "Ajouter" pour importer des photos.',
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
                            color: Colors.black.withValues(0.6)
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
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
