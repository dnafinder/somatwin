import 'dart:io';

import 'package:digital_twin/core/absi_table.dart';
import 'package:digital_twin/core/indices.dart';
import 'package:digital_twin/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

AbsiTable _table() => AbsiTable.parse(
      File('assets/absi_male.csv').readAsStringSync(),
      File('assets/absi_female.csv').readAsStringSync(),
    );

Measurements _male() => Measurements(
      sex: Sex.male,
      birthDate: DateTime(1968, 1, 1),
      takenOn: DateTime(2025, 6, 1),
      weight: 87,
      height: 173,
      waist: 107,
      hip: 103,
      wrist: 18,
      neck: 40,
      calf: 38,
      sbp: 128,
      dbp: 87,
      hr: 61,
    );

Measurements _female() => Measurements(
      sex: Sex.female,
      birthDate: DateTime(1980, 1, 1),
      takenOn: DateTime(2025, 6, 1),
      weight: 62,
      height: 165,
      waist: 78,
      hip: 99,
      wrist: 15.5,
      neck: 33,
      calf: 35,
      sbp: 118,
      dbp: 76,
      hr: 72,
    );

void main() {
  final absi = _table();
  statiTests();

  group('maschio 57 anni (referto CARDIOMET)', () {
    final m = _male();
    final r = computeReport(m, const Anamnesis(answered: true, parentsHypertensive: 1), absi);
    test('eta', () => expect(m.age, 57));
    test('rischio ipertensione: profilo ottimale e rapporto', () {
      for (final y in ['1', '2', '4']) {
        final risk = r.values['HT$y']!;
        final ideal = r.values['HTREF$y']!;
        expect(ideal, greaterThan(0));
        expect(risk, greaterThan(ideal));
        expect(r.values['HTX$y'], closeTo(risk / ideal, 1e-9));
        expect(r.byKey('HT$y')!.severity, risk > ideal ? Severity.alert : Severity.ok);
      }
    });
    final gold = <String, double>{
      'BMI': 28.7308,
      'BMI_CLASSIC': 29.0688,
      'BSA': 2.0,
      'BVOL': 86.1386,
      'GRANT': 9.6,
      'LORENZ': 67.3,
      'CREFF': 70.8,
      'CALFCORR': 35.0,
      'WHR': 1.04,
      'AVI': 22.9092,
      'WHTR': 0.62,
      'ABSI': 0.0867,
      'ABSI_Z': 0.7863,
      'CI': 1.3843,
      'BRI': 5.8533,
      'BAI': 27,
      'BF_CUN': 30.4828,
      'BMR': 1671,
      'BEE': 1735,
      'RFM': 31.6636,
      'NAVY': 30.6049,
      'FM': 26.52,
      'FFM': 60.48,
      'FMI': 8.861,
      'FFMI': 20.2078,
      'LBM_BOER': 62.4,
      'LBM_HUME': 57.7083,
      'LBM_JAMES': 63.329,
      'KATCH': 1676.3678,
      'BMR_MEAN': 1694.1226,
      'LBM': 61.1458,
      'FCM': 168.3545,
      'MAP': 100.2042,
      'AI': 0.41,
      'HRR': 107.3545,
      'MSI': 0.61,
      'RPP': 7808,
      'SV': 58,
      'SVPCT': 84,
      'CO': 3.5,
      'CIDX': 1.8,
      'LCWI': 401,
      'SVRI': 4.4,
      'EPWV': 9.4843,
    };
    gold.forEach((k, g) {
      test(k, () {
        final x = r.values[k];
        expect(x, isNotNull, reason: 'manca $k');
        expect(x!, closeTo(g, g.abs() * 0.002 + 0.0006), reason: k);
      });
    });
    test('pressione e frequenza in parole', () {
      expect(r.byKey('BP')!.comment, 'Normoteso');
      expect(r.byKey('HR')!.comment, 'Bradicardico');
      expect(r.values['BPZONE'], 0);
      expect(r.values['HRZONE'], -1);
    });
    test('AVI corretto, non il valore del referto (15.55)', () {
      expect(r.values['AVI']!, isNot(closeTo(15.5466, 0.5)));
    });
  });

  group('femmina 45 anni', () {
    final m = _female();
    final r = computeReport(m, const Anamnesis(answered: true, smoker: true), absi);
    final gold = <String, double>{
      'BMI': 23.0476,
      'BSA': 1.7,
      'GRANT': 10.6,
      'LORENZ': 57.5,
      'CREFF': 62.6,
      'WHR': 0.79,
      'AVI': 12.4767,
      'WHTR': 0.47,
      'ABSI_Z': -0.8008,
      'CI': 1.1674,
      'BRI': 2.8616,
      'BAI': 28,
      'BF_CUN': 33.4245,
      'BMR': 1265,
      'BEE': 1336,
      'RFM': 33.6923,
      'NAVY': 30.4236,
      'FM': 20.7232,
      'FFM': 41.2768,
      'FMI': 7.6118,
      'FFMI': 15.1614,
      'KATCH': 1261.5786,
      'BMR_MEAN': 1287.5262,
      'FCM': 179.6137,
      'MAP': 90.9793,
      'MSI': 0.79,
      'RPP': 8496,
      'EPWV': 7.3497,
    };
    gold.forEach((k, g) {
      test(k, () {
        final x = r.values[k];
        expect(x, isNotNull, reason: 'manca $k');
        expect(x!, closeTo(g, g.abs() * 0.002 + 0.0006), reason: k);
      });
    });
  });

  test('vita: soglia 94 cm uomini, 80 donne; il valore uguale alla soglia e\' sopra', () {
    Measurements w(Sex sex, double waist) => Measurements(
          sex: sex,
          birthDate: DateTime(1980, 1, 1),
          takenOn: DateTime(2025, 6, 1),
          weight: 70,
          height: 170,
          waist: waist,
          hip: 95,
          wrist: 17,
          neck: 36,
          calf: 36,
          sbp: 120,
          dbp: 80,
          hr: 65,
        );
    expect(waistRaised(w(Sex.male, 93.9)), isFalse);
    expect(waistRaised(w(Sex.male, 94)), isTrue);
    expect(waistRaised(w(Sex.female, 79.9)), isFalse);
    expect(waistRaised(w(Sex.female, 80)), isTrue);
  });

  test('BSA: media troncata, 1 decimale', () {
    expect(bsaTruncatedMean(87, 173, 0), 2.0);
    expect(bsaTruncatedMean(62, 165, 1), 1.7);
  });

  test('mround: half away from zero', () {
    expect(mround(2.5), 3);
    expect(mround(-2.5), -3);
    expect(mround(1.2345, 2), 1.23);
  });

  test('cls conta le soglie <= v', () {
    expect(cls(5, [10, 20]), 0);
    expect(cls(10, [10, 20]), 1);
    expect(cls(25, [10, 20]), 2);
  });

  test('ABSI: tabella chiusa agli estremi', () {
    expect(absi.lookup(1, Sex.male).sd, absi.lookup(2, Sex.male).sd);
    expect(absi.lookup(99, Sex.female).mean, absi.lookup(85, Sex.female).mean);
  });
}

void statiTests() {
  group('stati pressione e frequenza', () {
    Report rep(double sbp, double dbp, double hr) {
      final m = Measurements(
        sex: Sex.male,
        birthDate: DateTime(1968, 1, 1),
        takenOn: DateTime(2025, 6, 1),
        weight: 87,
        height: 173,
        waist: 107,
        hip: 103,
        wrist: 18,
        neck: 40,
        calf: 38,
        sbp: sbp,
        dbp: dbp,
        hr: hr,
      );
      return computeReport(m, const Anamnesis(), _table());
    }
  
    test('ipoteso, normoteso, iperteso', () {
      expect(rep(85, 55, 72).byKey('BP')!.comment, 'Ipoteso');
      expect(rep(89, 70, 72).byKey('BP')!.comment, 'Ipoteso');
      expect(rep(139, 89, 72).byKey('BP')!.comment, 'Normoteso');
      expect(rep(140, 85, 72).byKey('BP')!.comment, 'Iperteso');
      expect(rep(125, 90, 72).byKey('BP')!.comment, 'Iperteso');
      // un solo valore oltre soglia basta, anche con l'altro basso
      expect(rep(150, 55, 72).byKey('BP')!.comment, 'Iperteso');
      expect(rep(85, 95, 72).byKey('BP')!.comment, 'Iperteso');
      expect(rep(150, 55, 72).values['BPZONE'], 1);
    });
  
    test('bradicardico, eucardico, tachicardico (57 anni: 72 - 75 bpm)', () {
      expect(rep(120, 80, 60).byKey('HR')!.comment, 'Bradicardico');
      expect(rep(120, 80, 73).byKey('HR')!.comment, 'Eucardico');
      expect(rep(120, 80, 90).byKey('HR')!.comment, 'Tachicardico');
    });
  });
  }
