import 'dart:convert';

import 'package:digital_twin/core/models.dart';
import 'package:digital_twin/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  final birth = DateTime(1968, 1, 1);

  test('registro: misure separate per soggetto', () async {
    SharedPreferences.setMockInitialValues({});
    final st = Storage();
    final a = Subject(id: 'a', name: 'Mario', surname: 'Rossi', sex: Sex.male, birth: birth);
    final b = Subject(id: 'b', name: 'Anna', surname: 'Bianchi', sex: Sex.female, birth: DateTime(1980, 3, 2));
    await st.addSubject(a);
    await st.addSubject(b);
    await st.add(Record('1', _m(Sex.male, birth, DateTime(2025, 1, 1), 80), const Anamnesis(), subjectId: 'a'));
    await st.add(Record('2', _m(Sex.male, birth, DateTime(2025, 6, 1), 82), const Anamnesis(), subjectId: 'a'));
    await st.add(Record('3', _m(Sex.female, DateTime(1980, 3, 2), DateTime(2025, 2, 1), 60), const Anamnesis(),
        subjectId: 'b'));

    final subs = await st.loadSubjects();
    expect(subs.map((s) => s.fullName).toList(), ['Bianchi Anna', 'Rossi Mario']);
    final ra = await st.load('a');
    expect(ra.map((r) => r.id).toList(), ['2', '1']); // la piu' recente per prima
    expect((await st.load('b')).length, 1);
    expect(await st.counts(), {'a': 2, 'b': 1});

    await st.deleteSubject('a');
    expect(await st.load('a'), isEmpty);
    expect((await st.loadSubjects()).length, 1);
    expect((await st.load('b')).length, 1);
  });

  test('modifica del soggetto: sesso e nascita si propagano alle misure', () async {
    SharedPreferences.setMockInitialValues({});
    final st = Storage();
    final a = Subject(id: 'a', name: 'Mario', surname: 'Rossi', sex: Sex.male, birth: birth);
    await st.addSubject(a);
    await st.add(Record('1', _m(Sex.male, birth, DateTime(2025, 1, 1), 80), const Anamnesis(), subjectId: 'a'));
    await st.updateSubject(a.copyWith(sex: Sex.female, birth: DateTime(1970, 5, 5)));
    final r = (await st.load('a')).single;
    expect(r.m.sex, Sex.female);
    expect(r.m.birthDate, DateTime(1970, 5, 5));
  });

  test('migrazione: misure vecchie senza soggetto', () async {
    final old = [
      Record('1', _m(Sex.male, birth, DateTime(2025, 1, 1), 80), const Anamnesis()),
      Record('2', _m(Sex.male, birth, DateTime(2025, 6, 1), 82), const Anamnesis()),
      Record('3', _m(Sex.female, DateTime(1980, 3, 2), DateTime(2025, 2, 1), 60), const Anamnesis()),
    ];
    SharedPreferences.setMockInitialValues({
      'records_v1': jsonEncode(old.map((r) => r.toJson()).toList()),
    });
    final st = Storage();
    final subs = await st.loadSubjects();
    expect(subs.length, 2);
    final counts = await st.counts();
    expect(counts.values.toList()..sort(), [1, 2]);
    for (final s in subs) {
      expect((await st.load(s.id)).every((r) => r.subjectId == s.id), isTrue);
    }
    // una seconda lettura non crea altri soggetti
    expect((await st.loadSubjects()).length, 2);
  });
}
