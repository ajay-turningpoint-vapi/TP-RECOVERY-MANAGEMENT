import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:salesman_mobile/services/api_client.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

/// Downloads a server-side evidence attachment to local storage and hands
/// it to the OS to open (a PDF viewer for PDFs).
///
/// The `/api/attachments` endpoint needs an auth header, so an external
/// browser / `launchUrl` can't fetch it — it just fails silently. Instead
/// we pull the bytes with the access token, write them to a real file,
/// then open that file. If nothing on the device can open it, the file is
/// still downloaded and we tell the user where it went.
Future<void> downloadAndOpenAttachment(
  BuildContext context,
  ApiClient apiClient,
  String path,
) async {
  final navigator = Navigator.of(context);

  try {
    final res = await http.get(
      Uri.parse(apiClient.attachmentUrl(path)),
      headers: apiClient.attachmentAuthHeaders,
    );

    if (res.statusCode != 200) {
      showAppMessageAfter(navigator,
          message: 'Could not download the attachment (HTTP ${res.statusCode}).', isError: true);
      return;
    }

    // Prefer the app's external files dir (visible to file managers under
    // Android/data, no permission needed); fall back to internal storage.
    final baseDir = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
        await getApplicationDocumentsDirectory();
    final saveDir = Directory('${baseDir.path}/attachments');
    await saveDir.create(recursive: true);
    final fileName = path.split('/').last;
    final file = File('${saveDir.path}/$fileName');
    await file.writeAsBytes(res.bodyBytes, flush: true);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      showAppMessageAfter(navigator,
          message: 'Saved to:\n${file.path}\n\nNo app on this device could open it (${result.message}).',
          type: AppMessageType.info,
          title: 'Downloaded');
    }
  } catch (e) {
    showAppMessageAfter(navigator, message: 'Could not open the attachment: $e', isError: true);
  }
}
