import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Durable local storage for a queued action's attachment (a photo/PDF
/// picked while offline). The picker's own path (from `image_picker`/
/// `file_picker`) isn't safe to hold onto across an app restart or once its
/// originating dialog closes — this copies the bytes into the app's own
/// support directory instead, keyed by the queued action's id, so the file
/// is still there whenever the queue gets a chance to flush.
class AttachmentStaging {
  AttachmentStaging._();

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'pending_attachments'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies [bytes] into the staging directory as `<actionId>.<ext>`
  /// (`ext` derived from [contentType], matching ApiClient.uploadAttachment's
  /// own convention) and returns the local path.
  static Future<String> stage(String actionId, List<int> bytes, {required String contentType}) async {
    final ext = contentType == 'application/pdf' ? '.pdf' : '.jpg';
    final dir = await _dir();
    final file = File(p.join(dir.path, '$actionId$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<List<int>> read(String localPath) => File(localPath).readAsBytes();

  /// Best-effort cleanup once a staged attachment has either uploaded
  /// successfully or the queued action was discarded — a leftover file
  /// here is wasted disk space, never a correctness problem, so failures
  /// are swallowed.
  static Future<void> delete(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      /* best effort */
    }
  }
}
