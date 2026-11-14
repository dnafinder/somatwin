import 'package:flutter/material.dart';

import 'core/absi_table.dart';
import 'storage.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final absi = await loadAbsiTable();
  runApp(DigitalTwinApp(absi: absi));
}

class DigitalTwinApp extends StatelessWidget {
  final AbsiTable absi;
  const DigitalTwinApp({super.key, required this.absi});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Somatwin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Testo più grande: su telefono (web e APK) i corpi 11-12 erano illeggibili.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * 1.25)),
          child: child!,
        );
      },
      home: HomeScreen(absi: absi),
    );
  }
}
