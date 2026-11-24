import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Copies picked files/images into the app's private directory so they
/// survive the picker's temp-file cleanup.
class FileStorageService {
  static const _uuid = Uuid();

  Future<Directory> _dir(String folder) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, folder));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> saveBytes(Uint8List bytes, String originalName,
      {String folder = 'attachments'}) async {
    final d = await _dir(folder);
    final safe = originalName.replaceAll(RegExp(r'[^\w.\-\u0600-\u06FF]'), '_');
    final file = File(p.join(d.path, '${_uuid.v4().substring(0, 8)}_$safe'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<File> writeExport(String fileName, List<int> bytes) async {
    final d = await _dir('exports');
    final f = File(p.join(d.path, fileName));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> delete(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort; a missing file is not an error for the user.
    }
  }
}
