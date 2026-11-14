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
}
