/// Adattamento del corpo MakeHuman alle misure: macro sesso/eta'/peso,
/// scala all'altezza e circonferenze di collo, vita, fianchi, polpaccio, polso.
/// L'algoritmo e' lo stesso del riferimento Python (tools/ + test/golden).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/models.dart';
import 'mh_data.dart';

const List<String> kMhMeasures = [
  'neck-circ',
  'waist-circ',
  'hips-circ',
  'calf-circ',
  'wrist-circ',
];

/// Una sezione piana del corpo: punti dell'intersezione, in dm.
class _Loop {
  final List<double> p = []; // x,y,z consecutivi
  int get n => p.length ~/ 3;
  double get cx {
    var s = 0.0;
    for (var i = 0; i < p.length; i += 3) {
      s += p[i];
    }
    return s / n;
  }

  double get cy {
    var s = 0.0;
    for (var i = 1; i < p.length; i += 3) {
      s += p[i];
    }
    return s / n;
  }

  double get cz {
    var s = 0.0;
    for (var i = 2; i < p.length; i += 3) {
      s += p[i];
    }
    return s / n;
  }
}

class MhFit {
  final double w;
  final Map<String, double> m;
  final double scale;
  final double volumeL;
  final double targetVolumeL;
  final Map<String, double> circ;
  final Float64List verts; // dm, scalati all'altezza

  const MhFit(this.w, this.m, this.scale, this.volumeL, this.targetVolumeL, this.circ, this.verts);

  /// Falso se il volume del modello resta lontano dal peso (macro al limite).
  bool get volumeFitted => (volumeL - targetVolumeL).abs() / targetVolumeL < 0.03;
}

class MhFitter {
  final MhData d;
  MhFitter(this.d);

  void _add(Float64List v, String name, double w) {
    if (w.abs() < 1e-9) return;
    final t = d.targets[name];
    if (t == null) return;
    final idx = t.idx, dd = t.d;
    for (var i = 0; i < idx.length; i++) {
      final k = idx[i] * 3;
      v[k] += w * dd[i * 3];
      v[k + 1] += w * dd[i * 3 + 1];
      v[k + 2] += w * dd[i * 3 + 2];
    }
  }

  Float64List macro(Sex sex, int age, double w) {
    final g = sex == Sex.male ? 'male' : 'female';
    final ay = age.toDouble().clamp(25.0, 90.0).toDouble();
    final a01 = 0.5 + (ay - 25) / 130.0;
    final old = math.max(0.0, a01 * 2 - 1);
    final young = 1 - old;
    final wmin = math.max(0.0, 1 - 2 * w);
    final wmax = math.max(0.0, 2 * w - 1);
    final v = Float64List(d.nv * 3);
    for (var i = 0; i < v.length; i++) {
      v[i] = d.base[i];
    }
    for (final e in [('young', young), ('old', old)]) {
      final a = e.$1, aw = e.$2;
      if (aw <= 0) continue;
      _add(v, 'macrodetails/caucasian-$g-$a', aw);
      _add(v, 'macrodetails/universal-$g-$a-averagemuscle-minweight', aw * wmin);
      _add(v, 'macrodetails/universal-$g-$a-averagemuscle-maxweight', aw * wmax);
    }
    return v;
  }

  /// Applica le circonferenze e scala all'altezza. Ritorna (vertici, scala).
  (Float64List, double) withMeas(Float64List vm, Map<String, double> m, double heightCm) {
    final v = Float64List.fromList(vm);
    for (final e in m.entries) {
      if (e.value != 0) {
        _add(v, 'measure/measure-${e.key}-${e.value > 0 ? 'incr' : 'decr'}', e.value.abs());
      }
    }
    var ymin = double.infinity, ymax = -double.infinity;
    for (var i = 1; i < vm.length; i += 3) {
      if (vm[i] < ymin) ymin = vm[i];
      if (vm[i] > ymax) ymax = vm[i];
    }
    final s = (heightCm / 10.0) / (ymax - ymin);
    for (var i = 0; i < v.length; i++) {
      v[i] *= s;
    }
    return (v, s);
  }

  double volume(Float64List v) {
    final t = d.tris;
    var s = 0.0;
    for (var i = 0; i < t.length; i += 3) {
      final a = t[i] * 3, b = t[i + 1] * 3, c = t[i + 2] * 3;
      final bx = v[b], by = v[b + 1], bz = v[b + 2];
      final cx = v[c], cy = v[c + 1], cz = v[c + 2];
      s += v[a] * (by * cz - bz * cy) + v[a + 1] * (bz * cx - bx * cz) + v[a + 2] * (bx * cy - by * cx);
    }
    return s / 6.0;
  }

  /// Sezione del corpo con un piano (punto c, normale n); componenti connesse.
  List<_Loop> _loops(Float64List v, double cx, double cy, double cz, double nx, double ny, double nz) {
    final nv = d.nv;
    final h = Float64List(nv);
    for (var i = 0; i < nv; i++) {
      h[i] = (v[i * 3] - cx) * nx + (v[i * 3 + 1] - cy) * ny + (v[i * 3 + 2] - cz) * nz;
    }
    final node = <int, int>{};
    final parent = <int>[];
    final px = <double>[], py = <double>[], pz = <double>[];
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    int point(int u, int w) {
      final key = u < w ? u * nv + w : w * nv + u;
      final ex = node[key];
      if (ex != null) return ex;
      final f = h[u] / (h[u] - h[w]);
      final id = parent.length;
      parent.add(id);
      px.add(v[u * 3] + f * (v[w * 3] - v[u * 3]));
      py.add(v[u * 3 + 1] + f * (v[w * 3 + 1] - v[u * 3 + 1]));
      pz.add(v[u * 3 + 2] + f * (v[w * 3 + 2] - v[u * 3 + 2]));
      node[key] = id;
      return id;
    }

    final t = d.tris;
    for (var i = 0; i < t.length; i += 3) {
      final a = t[i], b = t[i + 1], c = t[i + 2];
      final pa = h[a] > 0, pb = h[b] > 0, pc = h[c] > 0;
      if (pa == pb && pb == pc) continue;
      final ids = <int>[];
      if (pa != pb) ids.add(point(a, b));
      if (pb != pc) ids.add(point(b, c));
      if (pc != pa) ids.add(point(c, a));
      if (ids.length == 2) {
        parent[find(ids[0])] = find(ids[1]);
      }
    }
    final groups = <int, _Loop>{};
    for (var i = 0; i < parent.length; i++) {
      final g = groups.putIfAbsent(find(i), () => _Loop());
      g.p..add(px[i])..add(py[i])..add(pz[i]);
    }
    return groups.values.toList();
  }

  /// Indici (antiorari) del guscio convesso di punti 2D.
  static List<int> hullIdx(List<double> xs, List<double> ys) {
    final n = xs.length;
    final ord = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final c = xs[a].compareTo(xs[b]);
        return c != 0 ? c : ys[a].compareTo(ys[b]);
      });
    double cross(int o, int a, int b) =>
        (xs[a] - xs[o]) * (ys[b] - ys[o]) - (ys[a] - ys[o]) * (xs[b] - xs[o]);
    final h = <int>[];
    for (final i in ord) {
      while (h.length >= 2 && cross(h[h.length - 2], h[h.length - 1], i) <= 0) {
        h.removeLast();
      }
      h.add(i);
    }
    final lower = h.length + 1;
    for (var k = ord.length - 2; k >= 0; k--) {
      final i = ord[k];
      while (h.length >= lower && cross(h[h.length - 2], h[h.length - 1], i) <= 0) {
        h.removeLast();
      }
      h.add(i);
    }
    if (h.length > 1) h.removeLast();
    return h;
  }

  /// Base del piano per la proiezione 2D: normale n.
  static (List<double>, List<double>) _basis(double nx, double ny, double nz) {
    final l = math.sqrt(nx * nx + ny * ny + nz * nz);
    nx /= l;
    ny /= l;
    nz /= l;
    final ref = ny.abs() < 0.9 ? [0.0, 1.0, 0.0] : [1.0, 0.0, 0.0];
    var e1 = [ny * ref[2] - nz * ref[1], nz * ref[0] - nx * ref[2], nx * ref[1] - ny * ref[0]];
    final le = math.sqrt(e1[0] * e1[0] + e1[1] * e1[1] + e1[2] * e1[2]);
    e1 = [e1[0] / le, e1[1] / le, e1[2] / le];
    final e2 = [ny * e1[2] - nz * e1[1], nz * e1[0] - nx * e1[2], nx * e1[1] - ny * e1[0]];
    return (e1, e2);
  }

  /// Guscio convesso della sezione: indici ordinati e perimetro (dm).
  (List<int>, double) _hull(_Loop l, double nx, double ny, double nz) {
    if (l.n < 3) return (const <int>[], 0.0);
    final (e1, e2) = _basis(nx, ny, nz);
    final xs = List<double>.filled(l.n, 0), ys = List<double>.filled(l.n, 0);
    for (var i = 0; i < l.n; i++) {
      final x = l.p[i * 3], y = l.p[i * 3 + 1], z = l.p[i * 3 + 2];
      xs[i] = x * e1[0] + y * e1[1] + z * e1[2];
      ys[i] = x * e2[0] + y * e2[1] + z * e2[2];
    }
    final h = hullIdx(xs, ys);
    var per = 0.0;
    for (var i = 0; i < h.length; i++) {
      final a = h[i], b = h[(i + 1) % h.length];
      per += math.sqrt(math.pow(xs[b] - xs[a], 2) + math.pow(ys[b] - ys[a], 2));
    }
    return (h, per);
  }

  /// Sezione scelta per una misura: lista di anelli (dm) con la stessa regola
  /// del riferimento. Ogni voce e' (componente, normale).
  List<(_Loop, List<double>)> _rings(Float64List v, String name, {bool bothSides = false}) {
    final t = d.targets['measure/measure-$name-incr']!;
    if (name == 'wrist-circ') {
      final ax = d.wristAxis;
      final out = <(_Loop, List<double>)>[];
      for (final side in bothSides ? const [1.0, -1.0] : const [1.0]) {
        var sx = 0.0, sy = 0.0, sz = 0.0;
        var n = 0;
        for (final i in t.idx) {
          if (v[i * 3] > 0) {
            sx += v[i * 3];
            sy += v[i * 3 + 1];
            sz += v[i * 3 + 2];
            n++;
          }
        }
        final cx = side * sx / n, cy = sy / n, cz = sz / n;
        final nx = side * ax[0];
        final comps = _loops(v, cx, cy, cz, nx, ax[1], ax[2]);
        _Loop? best;
        var bd = double.infinity;
        for (final c in comps) {
          final dd = math.sqrt(math.pow(c.cx - cx, 2) + math.pow(c.cy - cy, 2) + math.pow(c.cz - cz, 2));
          if (dd < bd) {
            bd = dd;
            best = c;
          }
        }
        if (best != null) out.add((best, [nx, ax[1], ax[2]]));
      }
      return out;
    }
    var ys = 0.0;
    for (final i in t.idx) {
      ys += v[i * 3 + 1];
    }
    final y = ys / t.idx.length;
    final comps = _loops(v, 0, y, 0, 0, 1, 0);
    final out = <(_Loop, List<double>)>[];
    const up = [0.0, 1.0, 0.0];
    if (name == 'calf-circ') {
      for (final side in bothSides ? const [1, -1] : const [1]) {
        _Loop? best;
        var bp = -1.0;
        for (final c in comps) {
          if (side * c.cx > 0.5) {
            final p = _hull(c, 0, 1, 0).$2;
            if (p > bp) {
              bp = p;
              best = c;
            }
          }
        }
        if (best != null) out.add((best, up));
      }
    } else {
      _Loop? best;
      var bp = -1.0;
      for (final c in comps) {
        if (c.cx.abs() < 0.6) {
          final p = _hull(c, 0, 1, 0).$2;
          if (p > bp) {
            bp = p;
            best = c;
          }
        }
      }
      if (best != null) out.add((best, up));
    }
    return out;
  }

  /// Circonferenza in cm.
  double circ(Float64List v, String name) {
    final r = _rings(v, name);
    if (r.isEmpty) return 0;
    final n = r.first.$2;
    return 10 * _hull(r.first.$1, n[0], n[1], n[2]).$2;
  }

  static double _solve(double Function(double) f, double lo, double hi, double target, int n) {
    var flo = f(lo) - target;
    final fhi = f(hi) - target;
    if (flo * fhi > 0) return flo.abs() < fhi.abs() ? lo : hi;
    for (var i = 0; i < n; i++) {
      final mid = (lo + hi) / 2;
      final fm = f(mid) - target;
      if (flo * fm <= 0) {
        hi = mid;
      } else {
        lo = mid;
        flo = fm;
      }
    }
    return (lo + hi) / 2;
  }

  MhFit fit(Measurements ms) {
    final sex = ms.sex;
    final age = ms.age;
    final target = {
      'neck-circ': ms.neck,
      'waist-circ': ms.waist,
      'hips-circ': ms.hip,
      'calf-circ': ms.calf,
      'wrist-circ': ms.wrist,
    };
    final m = {for (final k in kMhMeasures) k: 0.0};
    var w = 0.5;
    final targetVol = ms.weight / 1.010;
    for (var p = 0; p < 2; p++) {
      w = _solve((x) => volume(withMeas(macro(sex, age, x), m, ms.height).$1), 0.0, 1.0, targetVol, 14);
      final vm = macro(sex, age, w);
      for (final k in kMhMeasures) {
        m[k] = _solve((x) {
          final mm = Map<String, double>.from(m)..[k] = x;
          return circ(withMeas(vm, mm, ms.height).$1, k);
        }, -2.5, 3.5, target[k]!, 14);
      }
    }
    final vm = macro(sex, age, w);
    final (v, s) = withMeas(vm, m, ms.height);
    return MhFit(w, Map.of(m), s, volume(v), targetVol, {for (final k in kMhMeasures) k: circ(v, k)}, v);
  }

  /// Anelli misurati del modello finale: per tag, poligoni (guscio) in dm.
  Map<String, List<List<double>>> measuredRings(Float64List v) {
    final tags = {
      'neck': 'neck-circ',
      'waist': 'waist-circ',
      'hip': 'hips-circ',
      'calf': 'calf-circ',
      'wrist': 'wrist-circ',
    };
    final out = <String, List<List<double>>>{};
    tags.forEach((tag, name) {
      // vita e fianchi: il piano passa per la media dei vertici del target
      final rings = _rings(v, name, bothSides: name == 'calf-circ' || name == 'wrist-circ');
      final polys = <List<double>>[];
      for (final r in rings) {
        final (h, _) = _hull(r.$1, r.$2[0], r.$2[1], r.$2[2]);
        final poly = <double>[];
        for (final i in h) {
          poly..add(r.$1.p[i * 3])..add(r.$1.p[i * 3 + 1])..add(r.$1.p[i * 3 + 2]);
        }
        polys.add(poly);
      }
      out[tag] = polys;
    });
    return out;
  }

  /// Sezione del tronco a quota y (dm): punti con |x| piccolo, per il cuore.
  double torsoFrontZ(Float64List v, double y, double x0, double halfWidth) {
    final comps = _loops(v, 0, y, 0, 0, 1, 0);
    var best = -double.infinity;
    for (final c in comps) {
      if (c.cx.abs() >= 0.6) continue;
      for (var i = 0; i < c.n; i++) {
        if ((c.p[i * 3] - x0).abs() < halfWidth && c.p[i * 3 + 2] > best) best = c.p[i * 3 + 2];
      }
    }
    return best;
  }
}
