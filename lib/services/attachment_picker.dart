import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// Camera / gallery / PDF picker shared by every "attach evidence" button
/// in the app (Record Outcome forms, dispute chat threads). PDFs come back
/// as a bytes-backed [XFile] with `mimeType: 'application/pdf'` — the same
/// shape ApiClient.uploadAttachment already expects.
Future<XFile?> pickEvidenceFile(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text('Add attachment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48))),
          const SizedBox(height: 2),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE3EDFB), child: Icon(Icons.photo_camera, color: Color(0xFF0052CC))),
            title: const Text('Take photo', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFDCFCE7), child: Icon(Icons.photo_library, color: Color(0xFF16A34A))),
            title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFFEE2E2), child: Icon(Icons.picture_as_pdf, color: Color(0xFFDC2626))),
            title: const Text('Upload PDF', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return null;
  if (choice == 'pdf') {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (f == null) return null;
    final name = f.name.trim().isNotEmpty ? f.name.trim() : 'document.pdf';
    // The picker's own cached path is best — a real file means XFile.name
    // and readAsBytes both work. cross_file's io XFile.fromData otherwise
    // drops the name (XFile.name reads the path basename), which left the
    // attach button and the upload with an empty filename.
    if (f.path != null && f.path!.isNotEmpty && File(f.path!).existsSync()) {
      return XFile(f.path!, mimeType: 'application/pdf');
    }
    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;
    final dir = Directory('${Directory.systemTemp.path}/tp_evidence/${DateTime.now().millisecondsSinceEpoch}');
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/$name');
    await tmp.writeAsBytes(bytes);
    return XFile(tmp.path, mimeType: 'application/pdf');
  }
  return ImagePicker().pickImage(
    source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 85,
  );
}
