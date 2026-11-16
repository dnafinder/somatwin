import 'package:flutter_test/flutter_test.dart';
import 'package:digital_twin/ui/range_bar.dart';

void main() {
  test('RefRange.parse', () {
    final a = RefRange.parse('18.5 - 25')!;
    expect(a.lo, 18.5);
    expect(a.hi, 25);
    final b = RefRange.parse('0 - 0.82')!;
    expect(b.lo, isNull);
    expect(b.hi, 0.82);
    final c = RefRange.parse('-0.272 - 0.228')!;
    expect(c.lo, -0.272);
    expect(c.hi, 0.228);
    expect(RefRange.parse('< 24.5')!.hi, 24.5);
    expect(RefRange.parse('> 35')!.lo, 35);
    expect(RefRange.parse(''), isNull);
    expect(RefRange.parse('abc'), isNull);
  });
  test('colore del valore = zona della barra', () {
    expect(zoneColor('18.5 - 25', 17), kBarBlue);
    expect(zoneColor('18.5 - 25', 25), kBarGreen);
    expect(zoneColor('18.5 - 25', 26), kBarRed);
    expect(zoneColor('< 0.5', 0.6), kBarRed);
    expect(zoneColor('> 60', 70), kBarGreen);
    expect(zoneColor('> 33', 30), kBarBlue); // sotto la norma e' sempre azzurro
    expect(zoneColor('', 5), isNull);
  });
  test('scala a gradi: il valore uguale alla soglia sale', () {
    const cuts = [-0.272, 0.229, 0.798];
    expect(gradeOf(cuts, -1.0), 0);
    expect(gradeOf(cuts, -0.272), 1);
    expect(gradeOf(cuts, 0.228), 1);
    expect(gradeOf(cuts, 0.229), 2);
    expect(gradeOf(cuts, 0.798), 3);
    expect(gradeColor(cuts, -1.0), kBarGreen);
    expect(gradeColor(cuts, 0.0), kBarYellow);
    expect(gradeColor(cuts, 0.5), kBarOrange);
    expect(gradeColor(cuts, 1.2), kBarRed);
  });

  test('scala a due gradi: verde e rosso', () {
    const cuts = [0.229];
    expect(gradeColor(cuts, -2.0), kBarGreen);
    expect(gradeColor(cuts, 0.228), kBarGreen);
    expect(gradeColor(cuts, 0.229), kBarRed);
    expect(gradeColor(cuts, 2.5), kBarRed);
  });
}
