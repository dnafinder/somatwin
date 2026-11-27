import 'dart:convert';

import 'core/absi_table.dart';
import 'core/indices.dart';
import 'core/models.dart';
import 'storage.dart';

/// Marcatore e versione del file di backup. Cambiare la versione solo se il
/// formato smette di essere leggibile dalle versioni precedenti.
const kBackupFormat = 'somatwin-backup';
const kBackupVersion = 1;

/// Backup completo (soggetti e storico) in JSON.
String encodeBackup(List<Subject> subjects, List<Record> records, {DateTime? now}) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': kBackupFormat,
    'version': kBackupVersion,
    'exportedAt': (now ?? DateTime.now()).toIso8601String(),
    'subjects': [for (final s in subjects) s.toJson()],
    'records': [for (final r in records) r.toJson()],
  });
}

/// Legge un backup. Lancia [FormatException] con un messaggio leggibile se il
/// file non e' un backup di Somatwin o e' danneggiato.
Backup decodeBackup(String text) {
  Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    throw const FormatException('Il file non è un JSON valido.');
  }
  if (j is! Map<String, dynamic> || j['format'] != kBackupFormat) {
    throw const FormatException('Il file non è un backup di Somatwin.');
  }
  final v = j['version'];
  if (v is! num || v.toInt() > kBackupVersion) {
    throw const FormatException('Il backup viene da una versione più recente di Somatwin: aggiorna l\'app.');
  }
  try {
    final subjects = [
      for (final e in j['subjects'] as List<dynamic>) Subject.fromJson(e as Map<String, dynamic>),
    ];
    final records = [
      for (final e in j['records'] as List<dynamic>) Record.fromJson(e as Map<String, dynamic>),
    ];
    return Backup(subjects, records);
  } catch (_) {
    throw const FormatException('Il backup è danneggiato: dati mancanti o non validi.');
  }
}

/// Campo CSV (RFC 4180): tra virgolette se contiene separatore, virgolette o a capo.
String csvField(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// Colonne dei dati grezzi, nell'ordine in cui compaiono nel CSV.
const kCsvRawColumns = [
  'data',
  'eta',
  'sesso',
  'peso_kg',
  'altezza_cm',
  'vita_cm',
  'fianchi_cm',
  'polso_cm',
  'collo_cm',
  'polpaccio_cm',
  'pas_mmhg',
  'pad_mmhg',
  'fc_bpm',
  'anamnesi_compilata',
  'fumatore',
  'genitori_ipertesi',
  'antipertensivi',
  'stopbang_compilato',
  'russamento',
  'stanchezza',
  'apnee_osservate',
  'ipertensione_diagnosticata',
];

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _num(double v) => v.toString();

String _bit(bool b) => b ? '1' : '0';

/// CSV di un soggetto: una riga per misura, dalla piu' vecchia alla piu'
/// recente. Prima i dati grezzi, poi gli indici calcolati con le formule
/// correnti dell'app (un indice assente per una misura resta vuoto).
/// Separatore virgola, decimali con il punto, date AAAA-MM-GG.
String subjectCsv(List<Record> records, AbsiTable absi) {
  final rows = [...records]..sort((a, b) => a.m.takenOn.compareTo(b.m.takenOn));
  final reports = [for (final r in rows) computeReport(r.m, r.an, absi)];

  // Colonne degli indici: ordine di prima comparsa, intestazione "etichetta (unita')".
  final keys = <String>[];
  final headers = <String, String>{};
  for (final rep in reports) {
    for (final res in rep.results) {
      if (headers.containsKey(res.key)) continue;
      var h = res.unit.isEmpty ? res.label : '${res.label} (${res.unit})';
      if (headers.containsValue(h)) h = '$h [${res.key}]';
      keys.add(res.key);
      headers[res.key] = h;
    }
  }

  final out = StringBuffer();
  out.write([...kCsvRawColumns, for (final k in keys) headers[k]!].map(csvField).join(','));
  for (var i = 0; i < rows.length; i++) {
    final m = rows[i].m;
    final an = rows[i].an;
    final byKey = {for (final res in reports[i].results) res.key: res.value};
    final cells = <String>[
      _isoDate(m.takenOn),
      m.age.toString(),
      m.sex.label,
      _num(m.weight),
      _num(m.height),
      _num(m.waist),
      _num(m.hip),
      _num(m.wrist),
      _num(m.neck),
      _num(m.calf),
      _num(m.sbp),
      _num(m.dbp),
      _num(m.hr),
      _bit(an.answered),
      _bit(an.smoker),
      an.parentsHypertensive.toString(),
      _bit(an.onAntihypertensives),
      _bit(an.stopBangAnswered),
      _bit(an.snoring),
      _bit(an.tired),
      _bit(an.observedApnea),
      _bit(an.hypertensionDiagnosed),
      for (final k in keys) byKey[k] ?? '',
    ];
    out.write('\r\n');
    out.write(cells.map(csvField).join(','));
  }
  return out.toString();
}

/// Nome file sicuro: solo lettere e cifre ASCII, il resto diventa '_'.
String safeFileName(String s) {
  final t = s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return t.isEmpty ? 'soggetto' : t;
}

String backupFileName(DateTime now) => 'somatwin_backup_${_isoDate(now)}.json';

String csvFileName(Subject s) => 'somatwin_${safeFileName(s.fullName)}.csv';
