import 'dart:ui' show Size;

import 'package:digital_twin/twin/twin_view.dart';
import 'package:digital_twin/ui/guida_misure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ogni sezione ha un titolo, un testo e un distretto noto', () {
    const tags = {null, 'neck', 'waist', 'hip', 'wrist', 'calf', 'heart'};
    expect(kGuideSteps.length, 9);
    for (final s in kGuideSteps) {
      expect(s.title.isNotEmpty, true);
      expect(s.text.isNotEmpty, true);
      expect(tags.contains(s.tag), true, reason: s.title);
      expect(s.zoom, inInclusiveRange(1.0, 3.0));
    }
  });

  test('il fuoco finisce al centro della vista, a qualunque rotazione', () {
    const size = Size(400, 600);
    for (final yaw in [0.0, 0.5, 2.0, 4.0]) {
      final pr = TwinProjector(yaw, 2.0, size, 176, focus: [10.0, 120.0, -5.0]);
      final c = pr.project(10, 120, -5);
      expect(c.dx, closeTo(size.width / 2 + pr.ox, 1e-9));
      expect(c.dy, closeTo(size.height / 2, 1e-9));
    }
  });

  test('senza fuoco la proiezione resta quella di prima', () {
    const size = Size(400, 600);
    final a = TwinProjector(0.7, 1.0, size, 176);
    final b = TwinProjector(0.7, 1.0, size, 176, focus: [0.0, 88.0, 0.0]);
    final pa = a.project(12, 100, 7), pb = b.project(12, 100, 7);
    expect(pa.dx, closeTo(pb.dx, 1e-9));
    expect(pa.dy, closeTo(pb.dy, 1e-9));
  });
}
