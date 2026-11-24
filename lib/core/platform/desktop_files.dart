import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import 'platform_support.dart';

/// Picks an image.
///
/// Android/iOS: image_picker (gallery or camera, with compression) exactly as
/// before. Desktop: the system file dialog (file_picker), images only; the
/// camera is not offered there (callers hide the camera button).
Future<XFile?> pickImageFile({
  ImageSource source = ImageSource.gallery,
  int? imageQuality,
  double? maxWidth,
}) async {
  if (PlatformSupport.isMobile) {
    return ImagePicker().pickImage(source: source, imageQuality: imageQuality, maxWidth: maxWidth);
  }
  if (source == ImageSource.camera) return null;
  final f = await FilePicker.pickFile(type: FileType.image);
  final path = f?.path;
  if (f == null || path == null) return null;
  return XFile(path, name: f.name);
}

/// Shares an exported file (PDF, Excel, CSV, JSON backup…).
///
/// Android/iOS: the system share sheet, as before. Windows/Linux: a
/// "Save as…" dialog, then a snackbar with an "Open" button.
Future<void> shareOrSaveFile(BuildContext context, File file, {String? text, String? subject}) async {
  if (PlatformSupport.shareFiles) {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: text, subject: subject));
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final openLabel = context.tr('open_file');
  final uri = await FilePicker.saveFile(
    fileName: p.basename(file.path),
    bytes: await file.readAsBytes(),
    dialogTitle: subject ?? text,
  );
  if (uri == null) return; // cancelled
  final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  if (!context.mounted) return;
  final msg = context.trf('saved_to', {'path': path});
  messenger?.showSnackBar(SnackBar(
    content: Text(msg),
    action: SnackBarAction(label: openLabel, onPressed: () => OpenFilex.open(path)),
  ));
}
