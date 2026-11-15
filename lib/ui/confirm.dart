import 'package:flutter/material.dart';

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

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
