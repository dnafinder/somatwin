import 'dart:io';

import 'package:digital_twin/core/absi_table.dart';
import 'package:digital_twin/core/commento.dart';
import 'package:digital_twin/core/indices.dart';
import 'package:digital_twin/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

AbsiTable _table() => AbsiTable.parse(
      File('assets/absi_male.csv').readAsStringSync(),
      File('assets/absi_female.csv').readAsStringSync(),
    );

Measurements _m({
  required int age,
  required double weight,
  required double height,
  required double waist,
  required double hip,
  required double wrist,
  required double neck,
  required double calf,
  required double sbp,
  required double dbp,
  required double hr,
  Sex sex = Sex.male,
}) =>
    Measurements(
      sex: sex,
      birthDate: DateTime(2026 - age, 1, 1),
      takenOn: DateTime(2026, 6, 1),
      weight: weight,
      height: height,
      waist: waist,
      hip: hip,
      wrist: wrist,
      neck: neck,
      calf: calf,
      sbp: sbp,
      dbp: dbp,
      hr: hr,
    );

Comment _comment(Measurements m, [Anamnesis an = const Anamnesis()]) =>
    buildComment(computeReport(m, an, _table()), m);

CommentSection _sec(Comment c, String title) => c.sections.firstWhere((s) => s.title == title);

// Soggetti inventati.
final _standard = _m(age: 30, weight: 72, height: 178, waist: 80, hip: 95, wrist: 17, neck: 36, calf: 38, sbp: 118, dbp: 76, hr: 72);
final _muscolare = _m(age: 28, weight: 88, height: 180, waist: 82, hip: 100, wrist: 18, neck: 41, calf: 42, sbp: 120, dbp: 75, hr: 52);
final _sottopeso = _m(age: 25, weight: 52, height: 180, waist: 68, hip: 88, wrist: 16, neck: 33, calf: 32, sbp: 105, dbp: 65, hr: 62);
final _adiposo = _m(age: 50, weight: 105, height: 175, waist: 118, hip: 112, wrist: 19, neck: 45, calf: 41, sbp: 150, dbp: 95, hr: 55);

void main() {
  group('profilo', () {
    for (final e in {
      'standard': (_standard, Profilo.standard),
      'muscolare': (_muscolare, Profilo.muscolare),
      'sottopeso': (_sottopeso, Profilo.sottopeso),
      'adiposo': (_adiposo, Profilo.adiposo),
    }.entries) {
      test(e.key, () => expect(_comment(e.value.$1).profilo, e.value.$2));
    }
  });

  group('struttura', () {
    test('quattro aree, chiusura e due link', () {
      final c = _comment(_standard);
      expect(c.sections.map((s) => s.title).toList(), [
        'Peso e morfotipo',
        'Distribuzione del grasso',
        'Composizione corporea',
        'Cuore e pressione',
      ]);
      expect(c.closing, contains("l'interpretazione clinica spetta al medico"));
      expect(c.links.map((l) => l.url).toList(), [kUrlCardio, kUrlDoppiaLettura]);
      expect(c.ctaBody, contains('Self Coherence'));
    });

    test('stessi dati, stesso testo', () {
      expect(_comment(_adiposo).plainText, _comment(_adiposo).plainText);
    });

    test('nessuna etichetta di disturbo alimentare, in nessun profilo', () {
      for (final m in [_standard, _muscolare, _sottopeso, _adiposo]) {
        expect(_comment(m).plainText.toLowerCase(), isNot(contains('anoressia')));
      }
    });

    test('nessun prezzo nel testo', () {
      for (final m in [_standard, _muscolare, _sottopeso, _adiposo]) {
        expect(_comment(m).plainText, isNot(contains('€')));
      }
    });
  });

  group('contesto', () {
    test('standard: pressione e frequenza nella norma', () {
      final t = _sec(_comment(_standard), 'Cuore e pressione').text;
      expect(t, contains('La pressione è nella norma (118/76 mmHg).'));
      expect(t, contains('La frequenza a riposo è nella norma (72 bpm).'));
    });

    test('muscolare: BMI alto compatibile con massa muscolare, collo e frequenza coerenti', () {
      final c = _comment(_muscolare);
      expect(_sec(c, 'Peso e morfotipo').text, contains('compatibile con una massa muscolare importante'));
      expect(_sec(c, 'Peso e morfotipo').text, contains('coerente con la massa muscolare'));
      expect(_sec(c, 'Peso e morfotipo').esito, Esito.favorevole);
      final cuore = _sec(c, 'Cuore e pressione');
      expect(cuore.text, contains('compatibile con un condizionamento atletico'));
    });

    test('sottopeso: frequenza bassa da valutare con il medico', () {
      final c = _comment(_sottopeso);
      final cuore = _sec(c, 'Cuore e pressione');
      expect(cuore.text, contains('in un quadro di basso peso: va valutata con il medico'));
      expect(cuore.esito.index, greaterThanOrEqualTo(Esito.daOsservare.index));
      expect(_sec(c, 'Peso e morfotipo').text, contains('sottopeso'));
    });

    test('adiposo: frequenza bassa insolita, pressione legata al grasso', () {
      final c = _comment(_adiposo);
      final cuore = _sec(c, 'Cuore e pressione');
      expect(cuore.text, contains('combinazione insolita'));
      expect(cuore.text, contains("l'eccesso di grasso è uno dei fattori che la sostengono"));
      expect(cuore.esito, Esito.daApprofondire);
      expect(c.summary, contains('Emergono segnali'));
      expect(c.ctaLead, contains('approfondimento'));
      expect(c.lifestyle, isNotNull);
    });
  });

  group('rischio di ipertensione', () {
    test('compare solo con l\'anamnesi', () {
      final senza = _sec(_comment(_standard), 'Cuore e pressione').text;
      expect(senza, isNot(contains('ipertensione a 4 anni')));
      final con = _sec(_comment(_standard, const Anamnesis(answered: true)), 'Cuore e pressione').text;
      expect(con, contains('ipertensione a 4 anni'));
    });
  });
}
