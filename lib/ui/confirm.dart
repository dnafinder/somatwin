import 'package:flutter/material.dart';

import '../storage.dart';

/// Chiede conferma prima di eliminare una misura. true = elimina.
Future<bool> confirmDelete(BuildContext context, String when) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Eliminare la misura?'),
      content: Text('La misura del $when verra\' cancellata dallo storico. L\'operazione non si puo\' annullare.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Elimina')),
      ],
    ),
  );
  return ok ?? false;
}

/// Conferma prima di eliminare un soggetto con tutte le sue misure.
Future<bool> confirmDeleteSubject(BuildContext context, String who, int measures) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Eliminare il soggetto?'),
      content: Text(
          '$who verra\' cancellato dal registro${measures > 0 ? ' insieme a ${measures == 1 ? 'la sua misura' : 'tutte le sue $measures misure'}' : ''}. L\'operazione non si puo\' annullare.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Elimina')),
      ],
    ),
  );
  return ok ?? false;
}

/// Anteprima di un'importazione: chiede conferma prima di scrivere. true = importa.
Future<bool> confirmImport(BuildContext context, ImportSummary p) async {
  String n(int k, String one, String many) => '$k ${k == 1 ? one : many}';
  final skipped = p.subjectsSkipped + p.recordsSkipped;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Importare il backup?'),
      content: Text(
          'Verranno aggiunti ${n(p.subjectsAdded, 'soggetto', 'soggetti')} e ${n(p.recordsAdded, 'misura', 'misure')}.'
          '${skipped > 0 ? '\nSaltati perché già presenti o senza soggetto: ${n(p.subjectsSkipped, 'soggetto', 'soggetti')}, ${n(p.recordsSkipped, 'misura', 'misure')}.' : ''}'
          '\nI dati già nel registro non vengono toccati.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Importa')),
      ],
    ),
  );
  return ok ?? false;
}

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
