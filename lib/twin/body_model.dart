/// Modello corporeo parametrico: sezioni ellittiche impilate lungo uno scheletro.
///
/// Le sezioni misurate (collo, vita, fianchi, polso, polpaccio) hanno la
/// circonferenza esatta. Le altre sono stimate da proporzioni medie e
/// riscalate con un unico fattore, in modo che il volume del modello
/// coincida con peso / 1,010 kg/L (stesso BVOL del referto).
library;

import 'dart:math' as math;

import '../core/models.dart';

const int kRingPoints = 24;

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

  /// Sezioni in ordine di quota crescente.
  final List<Ring> rings;

  /// Se true esiste la copia speculare (x -> -x).
  final bool mirrored;

  const BodyPart(this.name, this.rings, {this.mirrored = false});

  double get volume {
    var v = 0.0;
    for (var i = 0; i + 1 < rings.length; i++) {
      v += (rings[i + 1].y - rings[i].y) * (rings[i].area + rings[i + 1].area) / 2;
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
  final vLo = _volume(_parts(m, lo));
  final vHi = _volume(_parts(m, hi));
  double s;
  var fitted = true;
  if (target <= vLo) {
    s = lo;
    fitted = false;
  } else if (target >= vHi) {
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
    {double cx = 0, double cz = 0, bool measured = false, String? tag}) {
  final a = semiAxis(circ, q);
  return Ring(y: y, a: a, b: q * a, cx: cx, cz: cz, measured: measured, tag: tag);
}

List<BodyPart> _parts(Measurements m, double s) {
  final h = m.height;
  final avg = (m.waist + m.hip) / 2;
  final chest = 1.07 * avg * s;

  // Torace e bacino
  final hipRing = _ell(0.52 * h, m.hip, 0.75, measured: true, tag: 'hip');
  final shoulder = _ell(0.81 * h, 0.98 * chest, 0.55);
  final torso = BodyPart('torso', [
    _ell(0.47 * h, 0.96 * m.hip * s, 0.75),
    hipRing,
    _ell(0.615 * h, m.waist, 0.78, measured: true, tag: 'waist'),
    _ell(0.72 * h, chest, 0.70),
    shoulder,
    _ell(0.84 * h, 1.12 * m.neck, 1.0),
  ]);

  final neck = BodyPart('neck', [
    _ell(0.84 * h, 1.12 * m.neck, 1.0),
    _ell(0.855 * h, m.neck, 1.0, measured: true, tag: 'neck'),
    _ell(0.87 * h, m.neck, 1.0),
  ]);

  // Gambe (una sola, specchiata)
  final legX = 0.5 * hipRing.a;
  final leg = BodyPart(
    'leg',
    [
      _ell(0.04 * h, 0.62 * m.calf * s, 1.0, cx: legX),
      _ell(0.20 * h, m.calf, 1.0, cx: legX, measured: true, tag: 'calf'),
      _ell(0.285 * h, 0.38 * m.hip * s, 1.0, cx: legX),
      _ell(0.39 * h, 0.52 * m.hip * s, 1.0, cx: legX),
      _ell(0.47 * h, 0.57 * m.hip * s, 1.0, cx: legX),
    ],
    mirrored: true,
  );

  final footA = semiAxis(0.62 * m.calf * s, 1.0);
  final foot = BodyPart(
    'foot',
    [
      Ring(y: 0.004 * h, a: 0.030 * h, b: 0.065 * h, cx: legX, cz: 0.055 * h),
      Ring(y: 0.020 * h, a: 0.034 * h, b: 0.070 * h, cx: legX, cz: 0.050 * h),
      Ring(y: 0.040 * h, a: footA, b: footA, cx: legX),
    ],
    mirrored: true,
  );

  // Braccia
  final ua = 0.30 * avg * s;
  final armX0 = shoulder.a - 2.0;
  double armCx(double y) => armX0 + (0.80 * h - y) * 0.2;
  Ring armRing(double y, double circ,
          {bool measured = false, String? tag}) =>
      _ell(y, circ, 1.0, cx: armCx(y), measured: measured, tag: tag);
  final arm = BodyPart(
    'arm',
    [
      armRing(0.43 * h, 1.2 * m.wrist * s),
      armRing(0.485 * h, m.wrist, measured: true, tag: 'wrist'),
      armRing(0.55 * h, 0.90 * ua),
      armRing(0.63 * h, 0.87 * ua),
      armRing(0.80 * h, ua),
    ],
    mirrored: true,
  );

  // Testa: ellissoide
  final yc = 0.935 * h;
  final rh = 0.065 * h;
  final ah = semiAxis(0.327 * h, 1.2);
  final headRings = <Ring>[];
  for (var k = -4; k <= 4; k++) {
    final t = k / 4.0;
    final sc = math.max(0.15, math.sqrt(math.max(0.0, 1 - t * t)));
    headRings.add(Ring(
      y: yc + t * rh,
      a: ah * sc,
      b: 1.2 * ah * sc,
      cz: 0.012 * h,
    ));
  }
  final head = BodyPart('head', headRings);

  return [torso, neck, leg, foot, arm, head];
}
