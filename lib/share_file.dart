import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

/// Condivide un file di testo: foglio di condivisione su Android, download sul web.
Future<void> shareTextFile(String name, String mime, String content) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(utf8.encode(content), mimeType: mime)],
    fileNameOverrides: [name],
  ));
}
