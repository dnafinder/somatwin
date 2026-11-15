import 'dart:io';

import 'package:digital_twin/core/absi_table.dart';
import 'package:digital_twin/core/indices.dart';
import 'package:digital_twin/core/models.dart';
import 'package:digital_twin/data_io.dart';
import 'package:digital_twin/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AbsiTable _table() => AbsiTable.parse(
      File('assets/absi_male.csv').readAsStringSync(),
      File('assets/absi_female.csv').readAsStringSync(),
    );

Measurements _m(Sex sex, DateTime birth, DateTime on, double w) => Measurements(
      sex: sex,
      birthDate: birth,
      takenOn: on,
      weight: w,
      height: 173,
      waist: 100,
      hip: 100,
      wrist: 17,
      neck: 38,
      calf: 37,
      sbp: 120,
      dbp: 80,
      hr: 65,
    );

/// Divide una riga CSV rispettando le virgolette (solo per i test).
List<String> _split(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var q = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (q) {
      if (c == '"' && i + 1 < line.length && line[i + 1] == '"') {
        cur.write('"');
        i++;
      } else if (c == '"') {
        q = false;
      } else {
        cur.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == ',') {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(cur.toString());
  return out;
}

void main() {
  final birth = DateTime(1968, 1, 1);
  final a = Subject(id: 'a', name: 'Mario', surname: 'Rossi', sex: Sex.male, birth: birth);
  final b = Subject(id: 'b', name: 'Anna', surname: 'Bianchi', sex: Sex.female, birth: DateTime(1980, 3, 2));
  final r1 = Record('1', _m(Sex.male, birth, DateTime(2025, 1, 1), 80), const Anamnesis(), subjectId: 'a');
  final r2 = Record(
      '2',
      _m(Sex.male, birth, DateTime(2025, 6, 1), 82),
      const Anamnesis(answered: true, smoker: true, parentsHypertensive: 1, onAntihypertensives: false),
      subjectId: 'a');
  final r3 = Record('3', _m(Sex.female, DateTime(1980, 3, 2), DateTime(2025, 2, 1), 60), const Anamnesis(),
      subjectId: 'b');

  group('backup JSON', () {
    test('andata e ritorno', () {
      final text = encodeBackup([a, b], [r1, r2, r3], now: DateTime(2025, 7, 1));
      final back = decodeBackup(text);
      expect(back.subjects.map((s) => s.toJson()).toList(), [a.toJson(), b.toJson()]);
      expect(back.records.map((r) => r.toJson()).toList(), [r1.toJson(), r2.toJson(), r3.toJson()]);
    });

    test('rifiuta file che non sono un backup', () {
      expect(() => decodeBackup('non json'), throwsFormatException);
      expect(() => decodeBackup('[1,2]'), throwsFormatException);
      expect(() => decodeBackup('{"format":"altro","version":1}'), throwsFormatException);
      expect(() => decodeBackup('{"format":"$kBackupFormat","version":${kBackupVersion + 1},"subjects":[],"records":[]}'),
          throwsFormatException);
      expect(() => decodeBackup('{"format":"$kBackupFormat","version":$kBackupVersion,"subjects":[{"id":"x"}],"records":[]}'),
          throwsFormatException);
    });
  });

  group('importazione', () {
    test('unione per id: seconda importazione non aggiunge nulla', () async {
      SharedPreferences.setMockInitialValues({});
      final st = Storage();
      await st.addSubject(a);
      await st.add(r1);
      final file = Backup([a, b], [r1, r2, r3]);

      final plan = await st.importBackup(file, dryRun: true);
      expect([plan.subjectsAdded, plan.subjectsSkipped, plan.recordsAdded, plan.recordsSkipped], [1, 1, 2, 1]);
      expect((await st.loadSubjects()).length, 1); // l'anteprima non scrive

      final done = await st.importBackup(file);
      expect([done.subjectsAdded, done.recordsAdded], [1, 2]);
      expect((await st.loadSubjects()).length, 2);
      expect((await st.load('a')).length, 2);
      expect((await st.load('b')).length, 1);

      final again = await st.importBackup(file);
      expect(again.nothingToAdd, isTrue);
      expect((await st.load('a')).length, 2);
    });

    test('misura senza soggetto: saltata', () async {
      SharedPreferences.setMockInitialValues({});
      final st = Storage();
      final orphan = Record('9', r1.m, const Anamnesis(), subjectId: 'zzz');
      final done = await st.importBackup(Backup([], [orphan]));
      expect([done.recordsAdded, done.recordsSkipped], [0, 1]);
    });

    test('esporta e reimporta in un registro vuoto', () async {
      SharedPreferences.setMockInitialValues({});
      final st = Storage();
      await st.addSubject(a);
      await st.addSubject(b);
      await st.add(r1);
      await st.add(r2);
      await st.add(r3);
      final all = await st.loadAll();
      final text = encodeBackup(all.subjects, all.records);

      SharedPreferences.setMockInitialValues({});
      final fresh = Storage();
      await fresh.importBackup(decodeBackup(text));
      expect((await fresh.loadSubjects()).map((s) => s.id).toSet(), {'a', 'b'});
      expect((await fresh.load('a')).map((r) => r.id).toList(), ['2', '1']);
    });
  });

  group('CSV', () {
    test('campi con virgola e virgolette', () {
      expect(csvField('abc'), 'abc');
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('di "x"'), '"di ""x"""');
    });

    test('nome file sicuro', () {
      expect(safeFileName("De Rossi D'Angelo"), 'De_Rossi_D_Angelo');
      expect(safeFileName('  '), 'soggetto');
    });

    test('una riga per misura, in ordine cronologico, dati grezzi e poi indici', () {
      final table = _table();
      final csv = subjectCsv([r2, r1], table);
      final lines = csv.split('\r\n');
      expect(lines.length, 3);
      final head = _split(lines[0]);
      expect(head.sublist(0, kCsvRawColumns.length), kCsvRawColumns);
      expect(head.length, greaterThan(kCsvRawColumns.length));

      final row1 = _split(lines[1]);
      final row2 = _split(lines[2]);
      expect(row1.length, head.length);
      expect(row2.length, head.length);
      expect(row1[0], '2025-01-01');
      expect(row2[0], '2025-06-01');
      expect(row1[2], 'Maschio');
      expect(double.parse(row1[3]), 80);
      expect(double.parse(row2[3]), 82);
      // anamnesi: r2 compilata, fumatore, un genitore iperteso
      expect(row2.sublist(13, 17), ['1', '1', '1', '0']);
      expect(row1.sublist(13, 17), ['0', '0', '0', '0']);

      // il primo indice coincide con quello del referto
      final rep = computeReport(r1.m, r1.an, table);
      expect(row1[kCsvRawColumns.length], rep.results.first.value);
    });

    test('nessuna misura: solo intestazione', () {
      final csv = subjectCsv([], _table());
      expect(csv.split('\r\n').length, 1);
      expect(_split(csv), kCsvRawColumns);
    });
  });
}
