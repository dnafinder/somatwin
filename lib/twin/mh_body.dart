/// Corpo MakeHuman adattato a una misura, pronto per il disegno.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/models.dart';
import 'mh_data.dart';
import 'mh_fit.dart';

class MhBody {
  final MhData data;
  final MhFit fit;

  /// Altezza in cm.
  final double height;

  /// Vertici in cm: x laterale, y dal suolo, z in avanti; centrati su x=0, z=0.
  final Float32List pos;
  final Float32List nor;

  /// Sezioni misurate (guscio dei punti, flat x,y,z in cm), per tag.
  final Map<String, List<List<double>>> rings;

  /// Centro del cuore (cm).
  final List<double> heart;

  final double _yWaist, _yHip, _yNeck, _yCalf;
  final List<List<double>> _wristC; // centri polso (cm), sinistro e destro

  MhBody._(this.data, this.fit, this.height, this.pos, this.nor, this.rings, this.heart, this._yWaist, this._yHip,
      this._yNeck, this._yCalf, this._wristC);

  factory MhBody.build(MhData data, Measurements m) {
    final f = MhFitter(data);
    final r = f.fit(m);
    final v = r.verts;
    final nv = data.nv;

    var ymin = double.infinity, zs = 0.0;
    for (var i = 0; i < nv; i++) {
      if (v[i * 3 + 1] < ymin) ymin = v[i * 3 + 1];
      zs += v[i * 3 + 2];
    }
    final zc = zs / nv;
    final rings = f.measuredRings(v);
    List<double> shiftPoly(List<double> p) {
      final o = List<double>.filled(p.length, 0);
      for (var i = 0; i < p.length; i += 3) {
        o[i] = p[i] * 10;
        o[i + 1] = (p[i + 1] - ymin) * 10;
        o[i + 2] = (p[i + 2] - zc) * 10;
      }
      return o;
    }

    final ringsCm = {for (final e in rings.entries) e.key: [for (final p in e.value) shiftPoly(p)]};

    final pos = Float32List(nv * 3);
    for (var i = 0; i < nv; i++) {
      pos[i * 3] = v[i * 3] * 10;
      pos[i * 3 + 1] = (v[i * 3 + 1] - ymin) * 10;
      pos[i * 3 + 2] = (v[i * 3 + 2] - zc) * 10;
    }
    final h = m.height;

    // normali ai vertici: somma delle normali di faccia (area)
    final nor = Float32List(nv * 3);
    final t = data.tris;
    for (var i = 0; i < t.length; i += 3) {
      final a = t[i] * 3, b = t[i + 1] * 3, c = t[i + 2] * 3;
      final ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1], uz = pos[b + 2] - pos[a + 2];
      final wx = pos[c] - pos[a], wy = pos[c + 1] - pos[a + 1], wz = pos[c + 2] - pos[a + 2];
      final nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
      for (final k in [a, b, c]) {
        nor[k] += nx;
        nor[k + 1] += ny;
        nor[k + 2] += nz;
      }
    }
    for (var i = 0; i < nv; i++) {
      final l = math.sqrt(nor[i * 3] * nor[i * 3] + nor[i * 3 + 1] * nor[i * 3 + 1] + nor[i * 3 + 2] * nor[i * 3 + 2]);
      if (l > 0) {
        nor[i * 3] /= l;
        nor[i * 3 + 1] /= l;
        nor[i * 3 + 2] /= l;
      }
    }

    double meanY(String tag) {
      final p = ringsCm[tag]!.first;
      var s = 0.0;
      for (var i = 1; i < p.length; i += 3) {
        s += p[i];
      }
      return s / (p.length / 3);
    }

    List<double> center(List<double> p) {
      var x = 0.0, y = 0.0, z = 0.0;
      final n = p.length / 3;
      for (var i = 0; i < p.length; i += 3) {
        x += p[i];
        y += p[i + 1];
        z += p[i + 2];
      }
      return [x / n, y / n, z / n];
    }

    // cuore: a sinistra dello sterno (+x), 72,5% dell'altezza, sulla superficie anteriore
    final yh = 0.725 * h;
    final yhDm = yh / 10 + ymin;
    final zFront = f.torsoFrontZ(v, yhDm, 0.5, 1.5);
    final heart = [5.0, yh, (zFront.isFinite ? (zFront - zc) * 10 : 12.0) + 0.3];

    return MhBody._(data, r, h, pos, nor, ringsCm, heart, meanY('waist'), meanY('hip'), meanY('neck'),
        meanY('calf'), [for (final p in ringsCm['wrist']!) center(p)]);
  }

  /// Colore base e miscela per distretto (0-255 per canale, rgb consecutivi).
  Float32List regionRgb(Map<String, Severity> sev) {
    const base = [78.0, 106.0, 128.0];
    List<double> sevRgb(Severity s) {
      switch (s) {
        case Severity.ok:
          return const [43.0, 191.0, 146.0];
        case Severity.watch:
          return const [242.0, 201.0, 76.0];
        case Severity.alert:
          return const [242.0, 118.0, 46.0];
        case Severity.info:
          return const [127.0, 183.0, 214.0];
      }
    }

    final nv = data.nv;
    final out = Float32List(nv * 3);
    final h = height;
    for (var i = 0; i < nv; i++) {
      final x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
      String? best;
      var bw = 0.0;
      void cand(String key, double w) {
        if (w > bw) {
          bw = w;
          best = key;
        }
      }

      double g(double dist, double sigma) {
        final q = dist / sigma;
        return math.exp(-0.5 * q * q);
      }

      if (x.abs() < 26) {
        cand('waist', g(y - _yWaist, 0.05 * h));
        cand('hip', g(y - _yHip, 0.045 * h));
      }
      if (x.abs() < 12 && y > 0.78 * h && y < 0.93 * h) cand('neck', g(y - _yNeck, 0.03 * h));
      if (y < 0.4 * h) cand('calf', g(y - _yCalf, 0.04 * h));
      for (final c in _wristC) {
        final dx = x - c[0], dy = y - c[1], dz = z - c[2];
        cand('wrist', g(math.sqrt(dx * dx + dy * dy + dz * dz), 6.0));
      }
      var r = base[0], gr = base[1], b = base[2];
      if (best != null && sev[best] != null) {
        final w = math.min(1.0, bw * 1.15);
        final s = sevRgb(sev[best]!);
        r += (s[0] - r) * w;
        gr += (s[1] - gr) * w;
        b += (s[2] - b) * w;
      }
      out[i * 3] = r;
      out[i * 3 + 1] = gr;
      out[i * 3 + 2] = b;
    }
    return out;
  }
}
