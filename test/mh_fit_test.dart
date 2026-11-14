import 'dart:convert';
import 'dart:io';

import 'package:digital_twin/core/models.dart';
import 'package:digital_twin/twin/mh_body.dart';
import 'package:digital_twin/twin/mh_data.dart';
import 'package:digital_twin/twin/mh_fit.dart';
import 'package:flutter_test/flutter_test.dart';

Measurements _m(Map<String, dynamic> c) {
  final k = (c['circ_in'] as List).map((e) => (e as num).toDouble()).toList();
  return Measurements(
    sex: (c['sex'] as int) == 0 ? Sex.male : Sex.female,
    birthDate: DateTime(2025 - (c['age'] as int), 1, 1),
    takenOn: DateTime(2025, 6, 1),
    weight: (c['kg'] as num).toDouble(),
    height: (c['h'] as num).toDouble(),
    neck: k[0],
    waist: k[1],
    hip: k[2],
    calf: k[3],
    wrist: k[4],
    sbp: 120,
    dbp: 80,
    hr: 65,
  );
}

void main() {
  late MhData data;
  late Map<String, dynamic> golden;

  setUpAll(() {
    data = MhData.parse(File('assets/mh/body.bin').readAsBytesSync());
    golden = json.decode(File('test/golden/mh_fit.json').readAsStringSync()) as Map<String, dynamic>;
  });

  test('dati MakeHuman: mesh e target', () {
    expect(data.nv, 13380);
    expect(data.tris.length, 26756 * 3);
    expect(data.targets.length, 22);
    expect(data.targets['measure/measure-waist-circ-incr']!.idx.length, 862);
  });

  for (final name in ['male_referto', 'female45', 'male30slim', 'female70heavy']) {
    test('adattamento $name = riferimento Python', () {
      final c = golden[name] as Map<String, dynamic>;
      final f = MhFitter(data);
      final sw = Stopwatch()..start();
      final r = f.fit(_m(c));
      // ignore: avoid_print
      print('$name: ${sw.elapsedMilliseconds} ms');
      expect(r.w, closeTo((c['w'] as num).toDouble(), 0.01));
      expect(r.scale, closeTo((c['s'] as num).toDouble(), 1e-3));
      expect(r.volumeL, closeTo((c['vol'] as num).toDouble(), 0.5));
      final gm = c['m'] as Map<String, dynamic>;
      for (final k in kMhMeasures) {
        expect(r.m[k]!, closeTo((gm[k] as num).toDouble(), 0.03), reason: k);
      }
      final gc = c['circ_out'] as Map<String, dynamic>;
      for (final k in kMhMeasures) {
        expect(r.circ[k]!, closeTo((gc[k] as num).toDouble(), 0.15), reason: k);
      }
      final probe = c['probe'] as Map<String, dynamic>;
      probe.forEach((i, xyz) {
        final p = (xyz as List).map((e) => (e as num).toDouble()).toList();
        final v = int.parse(i) * 3;
        for (var a = 0; a < 3; a++) {
          expect(r.verts[v + a], closeTo(p[a], 0.03), reason: 'vertice $i asse $a');
        }
      });
    });
  }

  test('corpo costruito: altezza, anelli, cuore, colori', () {
    final c = golden['male_referto'] as Map<String, dynamic>;
    final b = MhBody.build(data, _m(c));
    var ymin = double.infinity, ymax = -double.infinity;
    for (var i = 1; i < b.pos.length; i += 3) {
      if (b.pos[i] < ymin) ymin = b.pos[i];
      if (b.pos[i] > ymax) ymax = b.pos[i];
    }
    expect(ymin, closeTo(0, 1e-3));
    expect(ymax, closeTo(173, 0.01));
    for (final t in ['neck', 'waist', 'hip', 'calf', 'wrist']) {
      expect(b.rings[t], isNotEmpty, reason: t);
    }
    expect(b.rings['calf']!.length, 2);
    expect(b.rings['wrist']!.length, 2);
    expect(b.heart[1], closeTo(0.725 * 173, 1e-6));
    final rgb = b.regionRgb({'waist': Severity.alert, 'hip': Severity.ok});
    expect(rgb.length, data.nv * 3);
    // la vita e' arancione (alert), la testa resta di colore base
    var maxR = 0.0;
    for (var i = 0; i < data.nv; i++) {
      if (rgb[i * 3] > maxR) maxR = rgb[i * 3];
    }
    expect(maxR, greaterThan(200));
  });
}
