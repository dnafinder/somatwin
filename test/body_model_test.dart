import 'package:digital_twin/core/models.dart';
import 'package:digital_twin/twin/body_model.dart';
import 'package:flutter_test/flutter_test.dart';

Measurements _m(
        {Sex sex = Sex.male,
        double w = 87,
        double h = 173,
        double waist = 107,
        double hip = 103,
        double wrist = 18,
        double neck = 40,
        double calf = 38}) =>
    Measurements(
      sex: sex,
      birthDate: DateTime(1968, 1, 1),
      takenOn: DateTime(2025, 6, 1),
      weight: w,
      height: h,
      waist: waist,
      hip: hip,
      wrist: wrist,
      neck: neck,
      calf: calf,
      sbp: 128,
      dbp: 87,
      hr: 61,
    );

void main() {
  test('volume del modello = peso/1.010 (soggetto referto)', () {
    final b = buildBody(_m());
    expect(b.volumeFitted, isTrue);
    expect((b.modelVolumeCm3 - b.targetVolumeCm3).abs() / b.targetVolumeCm3, lessThan(0.005));
    expect(b.scale, inInclusiveRange(0.9, 1.1));
  });

  test('profilo femminile magro', () {
    final b = buildBody(_m(sex: Sex.female, w: 62, h: 165, waist: 78, hip: 99, wrist: 15.5, neck: 33, calf: 35));
    expect(b.volumeFitted, isTrue);
    expect(b.scale, inInclusiveRange(0.8, 1.2));
  });

  test('misure incoerenti: scala limitata, flag falso', () {
    final b = buildBody(_m(w: 200, waist: 70, hip: 80));
    expect(b.volumeFitted, isFalse);
    expect(b.scale, kScaleMax);
  });

  test('anelli misurati mantengono la circonferenza', () {
    final b = buildBody(_m());
    final waist = b.ringByTag('waist')!;
    // Ramanujan I: P = pi*(3(a+b) - sqrt((3a+b)(a+3b)))
    final a = waist.a;
    final c = waist.b;
    final per = 3.141592653589793 * (3 * (a + c) - _sqrt((3 * a + c) * (a + 3 * c)));
    expect(per, closeTo(107, 0.01));
    expect(c / a, closeTo(0.78, 1e-9));
    expect(b.ringByTag('neck'), isNotNull);
    expect(b.ringByTag('calf'), isNotNull);
    expect(b.ringByTag('wrist'), isNotNull);
    expect(b.ringByTag('hip'), isNotNull);
  });
}

double _sqrt(double x) {
  var r = x / 2;
  for (var i = 0; i < 40; i++) {
    r = 0.5 * (r + x / r);
  }
  return r;
}
