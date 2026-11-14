/// Modello corporeo parametrico: sezioni ellittiche interpolate con curve morbide.
///
/// Le sezioni misurate (collo, vita, fianchi, polso, polpaccio) hanno la
/// circonferenza esatta. Le altre sono stimate da proporzioni medie e
/// riscalate con un unico fattore, in modo che il volume del modello
/// coincida con peso / 1,010 kg/L (stesso BVOL del referto).
library;

import 'dart:math' as math;

import '../core/models.dart';

/// Punti per ogni sezione.
const int kRingPoints = 20;

class Vec3 {
  final double x;
  final double y;
  final double z;
  const Vec3(this.x, this.y, this.z);
}

class Ring {
  /// Quota dal suolo (cm).
  final double y;

  /// Semiasse laterale e sagittale (cm).
  final double a;
  final double b;

  /// Centro laterale e sagittale (cm).
  final double cx;
  final double cz;

  /// true = circonferenza misurata, false = stimata.
  final bool measured;

  /// 'neck', 'waist', 'hip', 'calf', 'wrist' per le sezioni misurate.
  final String? tag;

  const Ring({
    required this.y,
    required this.a,
    required this.b,
    this.cx = 0,
    this.cz = 0,
    this.measured = false,
    this.tag,
  });

  double get area => math.pi * a * b;

  Vec3 vertex(int j, {bool mirror = false}) {
    final ang = 2 * math.pi * j / kRingPoints;
    final x = cx + a * math.cos(ang);
    final z = cz + b * math.sin(ang);
    return Vec3(mirror ? -x : x, y, z);
  }
}

class BodyPart {
  final String name;

  /// Sezioni di definizione (quelle con tag sono le misurate).
  final List<Ring> rings;

  /// Sezioni interpolate, in ordine di quota crescente.
  final List<Ring> sections;

  /// Se true esiste la copia speculare (x -> -x).
  final bool mirrored;

  const BodyPart(this.name, this.rings, this.sections, {this.mirrored = false});

  double get volume {
    var v = 0.0;
    for (var i = 0; i + 1 < sections.length; i++) {
      v += (sections[i + 1].y - sections[i].y) * (sections[i].area + sections[i + 1].area) / 2;
    }
    return mirrored ? 2 * v : v;
  }
}

/// Semiasse laterale di un'ellisse con rapporto b/a = q e perimetro p
/// (approssimazione di Ramanujan).
double semiAxis(double p, double q) {
  final k = math.pi * (3 * (1 + q) - math.sqrt((3 + q) * (1 + 3 * q)));
  return p / k;
}

class BodyModel {
  final double height;
  final List<BodyPart> parts;

  /// Fattore applicato alle sezioni stimate.
  final double scale;
  final double targetVolumeCm3;
  final double modelVolumeCm3;

  /// false se il fattore e' stato limitato: peso e misure sono poco coerenti.
  final bool volumeFitted;

  const BodyModel({
    required this.height,
    required this.parts,
    required this.scale,
    required this.targetVolumeCm3,
    required this.modelVolumeCm3,
    required this.volumeFitted,
  });

  Ring? ringByTag(String tag) {
    for (final p in parts) {
      for (final r in p.rings) {
        if (r.tag == tag) return r;
      }
    }
    return null;
  }

  /// Posizione del cuore (lato sinistro del corpo = +x).
  Vec3 get heartCenter => Vec3(0.027 * height, 0.725 * height, 0.012 * height);
}

const double kScaleMin = 0.75;
const double kScaleMax = 1.25;

BodyModel buildBody(Measurements m) {
  final target = m.weight / 1.010 * 1000;

  var lo = kScaleMin;
  var hi = kScaleMax;
  double s;
  var fitted = true;
  if (target <= _volume(_parts(m, lo))) {
    s = lo;
    fitted = false;
  } else if (target >= _volume(_parts(m, hi))) {
    s = hi;
    fitted = false;
  } else {
    for (var i = 0; i < 60; i++) {
      final mid = (lo + hi) / 2;
      if (_volume(_parts(m, mid)) < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    s = (lo + hi) / 2;
  }
  final parts = _parts(m, s);
  return BodyModel(
    height: m.height,
    parts: parts,
    scale: s,
    targetVolumeCm3: target,
    modelVolumeCm3: _volume(parts),
    volumeFitted: fitted,
  );
}

double _volume(List<BodyPart> parts) {
  var v = 0.0;
  for (final p in parts) {
    v += p.volume;
  }
  return v;
}

Ring _ell(double y, double circ, double q,
    {double cx = 0, double cz = 0, String? tag}) {
  final a = semiAxis(circ, q);
  return Ring(y: y, a: a, b: q * a, cx: cx, cz: cz, measured: tag != null, tag: tag);
}

/// Chiude le estremita' con tre sezioni che si restringono.
List<Ring> _cap(List<Ring> r, double d) {
  const f = [
    [2.5, 0.12],
    [2.0, 0.45],
    [1.2, 0.80],
  ];
  Ring shrink(Ring o, double dy, double s) =>
      Ring(y: o.y + dy, a: o.a * s, b: o.b * s, cx: o.cx, cz: o.cz);
  final out = <Ring>[];
  for (final e in f) {
    out.add(shrink(r.first, -e[0] * d, e[1]));
  }
  out.addAll(r);
  for (final e in f.reversed) {
    out.add(shrink(r.last, e[0] * d, e[1]));
  }
  return out;
}

double _field(Ring r, int f) {
  switch (f) {
    case 0:
      return r.a;
    case 1:
      return r.b;
    case 2:
      return r.cx;
    default:
      return r.cz;
  }
}

/// Interpolazione cubica (Catmull-Rom) tra le sezioni, quota lineare.
List<Ring> _loft(List<Ring> r, int n) {
  final out = <Ring>[];
  final cnt = r.length;
  final span = r.last.y - r.first.y;
  double tg(int i, int f) {
    if (i == 0) return _field(r[1], f) - _field(r[0], f);
    if (i == cnt - 1) return _field(r[cnt - 1], f) - _field(r[cnt - 2], f);
    return (_field(r[i + 1], f) - _field(r[i - 1], f)) / 2;
  }

  for (var i = 0; i < cnt - 1; i++) {
    final c = math.max(2, (n * (r[i + 1].y - r[i].y) / span).round());
    for (var k = 0; k < c; k++) {
      final t = k / c;
      final t2 = t * t;
      final t3 = t2 * t;
      final v = List<double>.filled(4, 0);
      for (var f = 0; f < 4; f++) {
        v[f] = (2 * t3 - 3 * t2 + 1) * _field(r[i], f) +
            (t3 - 2 * t2 + t) * tg(i, f) +
            (-2 * t3 + 3 * t2) * _field(r[i + 1], f) +
            (t3 - t2) * tg(i + 1, f);
      }
      final tag = (k == 0) ? r[i].tag : null;
      out.add(Ring(
        y: r[i].y + (r[i + 1].y - r[i].y) * t,
        a: math.max(0.05, v[0]),
        b: math.max(0.05, v[1]),
        cx: v[2],
        cz: v[3],
        measured: tag != null,
        tag: tag,
      ));
    }
  }
  final l = r.last;
  out.add(Ring(y: l.y, a: math.max(0.05, l.a), b: math.max(0.05, l.b), cx: l.cx, cz: l.cz, tag: l.tag, measured: l.tag != null));
  return out;
}

BodyPart _part(String name, List<Ring> defs, double capD, int n, {bool mirrored = false}) =>
    BodyPart(name, defs, _loft(_cap(defs, capD), n), mirrored: mirrored);

List<BodyPart> _parts(Measurements m, double s) {
  final h = m.height;
  final avg = (m.waist + m.hip) / 2;
  final chest = 1.07 * avg * s;

  final hipRing = _ell(0.52 * h, m.hip, 0.75, cz: -0.006 * h, tag: 'hip');
  final belly = 0.004 * h +
      0.02 * h * ((m.waist / m.hip - 0.85) / 0.25).clamp(0.0, 1.0).toDouble();
  final shoulderA = semiAxis(0.98 * chest, 0.55);
  final legX = 0.5 * hipRing.a;
  final ua = 0.30 * avg * s;
  final armX0 = shoulderA - 2.0;
  double armCx(double y) => armX0 + (0.80 * h - y) * 0.2;
  Ring arm(double y, double circ, {String? tag}) =>
      _ell(y, circ, 1.0, cx: armCx(y), tag: tag);

  final torso = _part(
    'torso',
    [
      _ell(0.47 * h, 0.96 * m.hip * s, 0.75, cz: -0.004 * h),
      hipRing,
      _ell(0.615 * h, m.waist, 0.78, cz: belly, tag: 'waist'),
      _ell(0.72 * h, chest, 0.70, cz: 0.008 * h),
      _ell(0.81 * h, 0.98 * chest, 0.55, cz: -0.004 * h),
      _ell(0.84 * h, 1.12 * m.neck, 1.0),
    ],
    1.0,
    46,
  );

  final neck = _part(
    'neck',
    [
      _ell(0.84 * h, 1.12 * m.neck, 1.0),
      _ell(0.855 * h, m.neck, 1.0, cz: 0.004 * h, tag: 'neck'),
      _ell(0.87 * h, m.neck, 1.0, cz: 0.008 * h),
    ],
    0.5,
    8,
  );

  final yc = 0.935 * h;
  final rh = 0.065 * h;
  final ah = semiAxis(0.327 * h, 1.2);
  final headRings = <Ring>[];
  for (var k = -4; k <= 4; k++) {
    final t = k / 4.0;
    final sc = math.max(0.15, math.sqrt(math.max(0.0, 1 - t * t)));
    headRings.add(Ring(y: yc + t * rh, a: ah * sc, b: 1.2 * ah * sc, cz: 0.012 * h));
  }
  final head = _part('head', headRings, 0.6, 16);

  final ankle = _ell(0.04 * h, 0.62 * m.calf * s, 1.0, cx: legX);
  final leg = _part(
    'leg',
    [
      ankle,
      _ell(0.20 * h, m.calf, 1.0, cx: legX, tag: 'calf'),
      _ell(0.285 * h, 0.38 * m.hip * s, 1.0, cx: legX),
      _ell(0.39 * h, 0.52 * m.hip * s, 1.0, cx: legX),
      _ell(0.47 * h, 0.57 * m.hip * s, 1.0, cx: legX),
    ],
    0.6,
    40,
    mirrored: true,
  );

  final foot = _part(
    'foot',
    [
      Ring(y: 0.004 * h, a: 0.030 * h, b: 0.065 * h, cx: legX, cz: 0.055 * h),
      Ring(y: 0.020 * h, a: 0.034 * h, b: 0.070 * h, cx: legX, cz: 0.050 * h),
      Ring(y: 0.040 * h, a: ankle.a, b: ankle.b, cx: legX),
    ],
    0.3,
    8,
    mirrored: true,
  );

  final armPart = _part(
    'arm',
    [
      arm(0.43 * h, 1.2 * m.wrist * s),
      arm(0.485 * h, m.wrist, tag: 'wrist'),
      arm(0.55 * h, 0.90 * ua),
      arm(0.63 * h, 0.87 * ua),
      arm(0.72 * h, 0.98 * ua),
      arm(0.80 * h, ua),
    ],
    0.7,
    34,
    mirrored: true,
  );

  return [torso, neck, head, leg, foot, armPart];
}
