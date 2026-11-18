import 'package:digital_twin/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('salvataggi vecchi senza i campi nuovi si leggono ancora', () {
    final a = Anamnesis.fromJson({'answered': true, 'smoker': false, 'php': 1, 'hp': false});
    expect(a.cvEvent, false);
    expect(a.highTriglycerides, false);
    expect(a.lowHdl, false);
    expect(a.highGlucose, false);
    expect(a.parentsHypertensive, 1);
  });

  test('andata e ritorno JSON con i campi nuovi', () {
    const a = Anamnesis(
        answered: true, smoker: true, parentsHypertensive: 2, cvEvent: true, highTriglycerides: true, lowHdl: true, highGlucose: true);
    final b = Anamnesis.fromJson(a.toJson());
    expect(b.cvEvent, true);
    expect(b.highTriglycerides, true);
    expect(b.lowHdl, true);
    expect(b.highGlucose, true);
    expect(b.smoker, true);
    expect(b.parentsHypertensive, 2);
  });
}
