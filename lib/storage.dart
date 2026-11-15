import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/absi_table.dart';
import 'core/models.dart';

/// Soggetto del registro: i dati che non cambiano mai.
class Subject {
  final String id;
  final String name;
  final String surname;
  final Sex sex;
  final DateTime birth;

  const Subject({
    required this.id,
    required this.name,
    required this.surname,
    required this.sex,
    required this.birth,
  });

  String get fullName => '$surname $name'.trim();

  Subject copyWith({String? name, String? surname, Sex? sex, DateTime? birth}) => Subject(
        id: id,
        name: name ?? this.name,
        surname: surname ?? this.surname,
        sex: sex ?? this.sex,
        birth: birth ?? this.birth,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'surname': surname, 'sex': sex.code, 'birth': birth.toIso8601String()};

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String,
        name: j['name'] as String,
        surname: j['surname'] as String,
        sex: (j['sex'] as num).toInt() == 0 ? Sex.male : Sex.female,
        birth: DateTime.parse(j['birth'] as String),
      );
}

/// Una misura, associata a un soggetto.
class Record {
  final String id;
  final String subjectId;
  final Measurements m;
  final Anamnesis an;

  const Record(this.id, this.m, this.an, {this.subjectId = ''});

  Record withSubject(String sid) => Record(id, m, an, subjectId: sid);

  Map<String, dynamic> toJson() => {'id': id, 'sid': subjectId, 'm': m.toJson(), 'an': an.toJson()};

  factory Record.fromJson(Map<String, dynamic> j) => Record(
        j['id'] as String,
        Measurements.fromJson(j['m'] as Map<String, dynamic>),
        Anamnesis.fromJson(j['an'] as Map<String, dynamic>),
        subjectId: (j['sid'] as String?) ?? '',
      );
}

/// Contenuto di un file di backup, gia' letto e controllato.
class Backup {
  final List<Subject> subjects;
  final List<Record> records;
  const Backup(this.subjects, this.records);
}

/// Esito (o anteprima) di un'importazione.
class ImportSummary {
  final int subjectsAdded;
  final int subjectsSkipped;
  final int recordsAdded;
  final int recordsSkipped;
  const ImportSummary(this.subjectsAdded, this.subjectsSkipped, this.recordsAdded, this.recordsSkipped);

  bool get nothingToAdd => subjectsAdded == 0 && recordsAdded == 0;
}

/// Registro e storico locali (solo sul dispositivo).
class Storage {
  static const _key = 'records_v1';
  static const _subjectsKey = 'subjects_v1';

  Future<List<Record>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => Record.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Subject>> _loadSubjectsRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subjectsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => Subject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<Record> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  Future<void> _saveSubjects(List<Subject> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subjectsKey, jsonEncode(list.map((s) => s.toJson()).toList()));
  }

  /// Le misure salvate prima del registro non hanno soggetto: ne viene creato
  /// uno per ogni coppia sesso e data di nascita, da rinominare a mano.
  Future<void> _migrate() async {
    final records = await _loadRaw();
    if (records.every((r) => r.subjectId.isNotEmpty)) return;
    final subjects = await _loadSubjectsRaw();
    final byKey = <String, Subject>{};
    var n = subjects.length;
    final out = <Record>[];
    for (final r in records) {
      if (r.subjectId.isNotEmpty) {
        out.add(r);
        continue;
      }
      final k = '${r.m.sex.code}|${r.m.birthDate.toIso8601String()}';
      var s = byKey[k];
      if (s == null) {
        n++;
        s = Subject(
          id: 'old${DateTime.now().microsecondsSinceEpoch}_$n',
          name: '$n',
          surname: 'Soggetto',
          sex: r.m.sex,
          birth: r.m.birthDate,
        );
        byKey[k] = s;
        subjects.add(s);
      }
      out.add(r.withSubject(s.id));
    }
    await _saveSubjects(subjects);
    await _save(out);
  }

  Future<List<Subject>> loadSubjects() async {
    await _migrate();
    final list = await _loadSubjectsRaw();
    list.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return list;
  }

  Future<void> addSubject(Subject s) async {
    final list = await _loadSubjectsRaw();
    list.add(s);
    await _saveSubjects(list);
  }

  /// Modifica un soggetto e allinea sesso e data di nascita delle sue misure.
  Future<void> updateSubject(Subject s) async {
    final list = await _loadSubjectsRaw();
    final i = list.indexWhere((x) => x.id == s.id);
    if (i >= 0) list[i] = s;
    await _saveSubjects(list);
    final records = await _loadRaw();
    final fixed = [
      for (final r in records)
        r.subjectId == s.id
            ? Record(r.id, r.m.withIdentity(s.sex, s.birth), r.an, subjectId: s.id)
            : r,
    ];
    await _save(fixed);
  }

  /// Elimina il soggetto e tutte le sue misure.
  Future<void> deleteSubject(String id) async {
    final list = await _loadSubjectsRaw();
    list.removeWhere((s) => s.id == id);
    await _saveSubjects(list);
    final records = await _loadRaw();
    records.removeWhere((r) => r.subjectId == id);
    await _save(records);
  }

  /// Misure di un soggetto, la piu' recente per prima.
  Future<List<Record>> load(String subjectId) async {
    await _migrate();
    final list = (await _loadRaw()).where((r) => r.subjectId == subjectId).toList();
    list.sort((a, b) => b.m.takenOn.compareTo(a.m.takenOn));
    return list;
  }

  /// Numero di misure per soggetto.
  Future<Map<String, int>> counts() async {
    final out = <String, int>{};
    for (final r in await _loadRaw()) {
      out[r.subjectId] = (out[r.subjectId] ?? 0) + 1;
    }
    return out;
  }

  Future<void> add(Record r) async {
    final list = await _loadRaw();
    list.add(r);
    await _save(list);
  }

  /// Sostituisce una misura esistente (correzione di un errore di inserimento).
  Future<void> update(Record r) async {
    final list = await _loadRaw();
    final i = list.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      list[i] = r;
    } else {
      list.add(r);
    }
    await _save(list);
  }

  Future<void> delete(String id) async {
    final list = await _loadRaw();
    list.removeWhere((r) => r.id == id);
    await _save(list);
  }

  /// Tutto il registro, per il backup.
  Future<Backup> loadAll() async {
    await _migrate();
    return Backup(await _loadSubjectsRaw(), await _loadRaw());
  }

  /// Unisce un backup al registro. Si riconosce tutto dall'id: un soggetto o
  /// una misura gia' presenti non vengono toccati, una misura il cui soggetto
  /// non e' ne' nel registro ne' nel file viene saltata. Con [dryRun] calcola
  /// l'esito senza scrivere.
  Future<ImportSummary> importBackup(Backup b, {bool dryRun = false}) async {
    await _migrate();
    final subjects = await _loadSubjectsRaw();
    final records = await _loadRaw();
    final subjectIds = {for (final s in subjects) s.id};
    final recordIds = {for (final r in records) r.id};
    var subjectsAdded = 0, subjectsSkipped = 0, recordsAdded = 0, recordsSkipped = 0;
    for (final s in b.subjects) {
      if (subjectIds.add(s.id)) {
        subjects.add(s);
        subjectsAdded++;
      } else {
        subjectsSkipped++;
      }
    }
    for (final r in b.records) {
      if (!subjectIds.contains(r.subjectId) || !recordIds.add(r.id)) {
        recordsSkipped++;
        continue;
      }
      records.add(r);
      recordsAdded++;
    }
    if (!dryRun) {
      await _saveSubjects(subjects);
      await _save(records);
    }
    return ImportSummary(subjectsAdded, subjectsSkipped, recordsAdded, recordsSkipped);
  }
}

Future<AbsiTable> loadAbsiTable() async {
  final m = await rootBundle.loadString('assets/absi_male.csv');
  final f = await rootBundle.loadString('assets/absi_female.csv');
  return AbsiTable.parse(m, f);
}
