/// Vista 3D del gemello digitale: mappa a colori.
///
/// Superficie piena e ombreggiata, disegnata con un'unica chiamata
/// drawVertices ordinata per profondita'. Il colore sfuma dove la misura
/// e' fuori norma. Il cuore pulsa alla frequenza misurata.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/models.dart';
import '../ui/theme.dart';
import 'body_model.dart';

const int _n = kRingPoints;

const List<double> _base = [78, 106, 128];

List<double> _sevRgb(Severity s) {
  switch (s) {
    case Severity.ok:
      return const [43, 191, 146];
    case Severity.watch:
      return const [242, 201, 76];
    case Severity.alert:
      return const [242, 118, 46];
    case Severity.info:
      return const [127, 183, 214];
  }
}

/// Distretto e peso di colore per una sezione di un dato segmento.
({String? key, double w}) _region(String part, double y, double h) {
  final cands = <(String, double, double)>[];
  switch (part) {
    case 'torso':
      cands.add(('waist', 0.615 * h, 0.05 * h));
      cands.add(('hip', 0.52 * h, 0.045 * h));
    case 'neck':
      cands.add(('neck', 0.855 * h, 0.5 * h));
    case 'leg':
      cands.add(('calf', 0.20 * h, 0.04 * h));
    case 'arm':
      cands.add(('wrist', 0.485 * h, 0.035 * h));
  }
  String? best;
  var bw = 0.0;
  for (final c in cands) {
    final z = (y - c.$2) / c.$3;
    final w = math.exp(-0.5 * z * z);
    if (w > bw) {
      bw = w;
      best = c.$1;
    }
  }
  return (key: best, w: math.min(1.0, bw * 1.15));
}

/// Copia (eventualmente speculare) di un segmento, con geometria precalcolata.
class _Copy {
  final BodyPart part;
  final bool mirror;
  final int s;
  final Float32List pos;
  final Float32List nor;
  final Float32List rgb;
  final Float32List sx;
  final Float32List sy;
  final Float32List sz;
  final Float32List nz2;
  final Float32List lam;

  _Copy._(this.part, this.mirror, this.s, this.pos, this.nor, this.rgb)
      : sx = Float32List(s * _n),
        sy = Float32List(s * _n),
        sz = Float32List(s * _n),
        nz2 = Float32List(s * _n),
        lam = Float32List(s * _n);

  factory _Copy(BodyPart part, bool mirror, double h, Map<String, Severity> sev) {
    final secs = part.sections;
    final s = secs.length;
    final pos = Float32List(s * _n * 3);
    final nor = Float32List(s * _n * 2);
    final rgb = Float32List(s * 3);
    for (var i = 0; i < s; i++) {
      final r = secs[i];
      final rg = _region(part.name, r.y, h);
      var col = _base;
      if (rg.key != null && sev[rg.key] != null) {
        final sv = _sevRgb(sev[rg.key]!);
        col = [
          _base[0] + (sv[0] - _base[0]) * rg.w,
          _base[1] + (sv[1] - _base[1]) * rg.w,
          _base[2] + (sv[2] - _base[2]) * rg.w,
        ];
      }
      rgb[i * 3] = col[0];
      rgb[i * 3 + 1] = col[1];
      rgb[i * 3 + 2] = col[2];
      for (var j = 0; j < _n; j++) {
        final th = 2 * math.pi * j / _n;
        final x = r.cx + r.a * math.cos(th);
        final z = r.cz + r.b * math.sin(th);
        final k = i * _n + j;
        pos[k * 3] = mirror ? -x : x;
        pos[k * 3 + 1] = r.y;
        pos[k * 3 + 2] = z;
        var nx = math.cos(th) / r.a;
        var nz = math.sin(th) / r.b;
        final l = math.sqrt(nx * nx + nz * nz);
        if (l > 0) {
          nx /= l;
          nz /= l;
        }
        nor[k * 2] = mirror ? -nx : nx;
        nor[k * 2 + 1] = nz;
      }
    }
    return _Copy._(part, mirror, s, pos, nor, rgb);
  }
}

class _Quad {
  final _Copy c;
  final int i;
  final int j;
  final double z;
  _Quad(this.c, this.i, this.j, this.z);
}

class TwinGeometry {
  final BodyModel model;
  final List<_Copy> copies = [];

  TwinGeometry(this.model, Map<String, Severity> sev) {
    for (final p in model.parts) {
      copies.add(_Copy(p, false, model.height, sev));
      if (p.mirrored) copies.add(_Copy(p, true, model.height, sev));
    }
  }
}

/// Proiezione condivisa da disegno e hit-test.
class TwinProjector {
  final double yaw;
  final double zoom;
  final Size size;
  final double height;
  late final double cy = math.cos(yaw);
  late final double sy = math.sin(yaw);
  static const double pitch = 0.08;
  late final double cp = math.cos(pitch);
  late final double sp = math.sin(pitch);
  late final double d = height * 2.6;
  late final double base =
      math.min(size.height * 0.90 / height, size.width * 0.62 / (height * 0.5)) * zoom;
  late final double ox = -size.width * 0.08;

  TwinProjector(this.yaw, this.zoom, this.size, this.height);

  Offset project(double x, double y, double z) {
    final py = y - height * 0.5;
    final x1 = x * cy + z * sy;
    final z1 = -x * sy + z * cy;
    final y2 = py * cp - z1 * sp;
    final z2 = py * sp + z1 * cp;
    final k = base * d / (d - z2);
    return Offset(size.width / 2 + ox + x1 * k, size.height / 2 - y2 * k);
  }
}

class TwinPainter extends CustomPainter {
  final TwinGeometry geo;
  final BodyModel? previous;
  final Map<String, Severity> severity;
  final Map<String, String> labels;
  final double yaw;
  final double zoom;
  final double time;
  final double heartRate;

  TwinPainter({
    required this.geo,
    required this.previous,
    required this.severity,
    required this.labels,
    required this.yaw,
    required this.zoom,
    required this.time,
    required this.heartRate,
  });

  BodyModel get model => geo.model;

  Color _sevColor(String key) => sevColor(severity[key] ?? Severity.info);

  double _pulse() {
    var period = 60.0 / math.max(30.0, heartRate);
    period = period.clamp(0.35, 2.0).toDouble();
    final phase = (time / period) % 1.0;
    if (phase < 0.15) return math.sin(phase / 0.15 * math.pi);
    if (phase < 0.30) return 0.35 * math.sin((phase - 0.15) / 0.15 * math.pi);
    return 0.0;
  }

  /// Punto del bordo piu' a destra di una sezione misurata.
  Map<String, Offset> anchors(TwinProjector pr) {
    final out = <String, Offset>{};
    for (final part in model.parts) {
      for (final r in part.rings) {
        if (!r.measured || r.tag == null) continue;
        Offset? best;
        for (final mirror in part.mirrored ? const [false, true] : const [false]) {
          for (var j = 0; j < _n; j++) {
            final v = r.vertex(j, mirror: mirror);
            final p = pr.project(v.x, v.y, v.z);
            if (best == null || p.dx > best.dx) best = p;
          }
        }
        if (best != null) out[r.tag!] = best;
      }
    }
    final c = model.heartCenter;
    out['heart'] = pr.project(c.x, c.y, c.z);
    return out;
  }

  void _drawGround(Canvas canvas, TwinProjector pr) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = kWireColor.withOpacity(0.18);
    for (final rad in [28.0, 52.0]) {
      final path = Path();
      for (var i = 0; i <= 48; i++) {
        final t = 2 * math.pi * i / 48;
        final p = pr.project(rad * math.cos(t), 0, rad * math.sin(t));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  /// Misura precedente: solo i contorni delle sezioni misurate, in grigio.
  void _drawGhost(Canvas canvas, TwinProjector pr, BodyModel prev) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = kGhostColor.withOpacity(0.7);
    for (final part in prev.parts) {
      for (final r in part.sections) {
        if (r.tag == null) continue;
        for (final mirror in part.mirrored ? const [false, true] : const [false]) {
          final path = Path();
          for (var j = 0; j <= _n; j++) {
            final v = r.vertex(j % _n, mirror: mirror);
            final p = pr.project(v.x, v.y, v.z);
            j == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, paint);
        }
      }
    }
  }

  void _drawMesh(Canvas canvas, TwinProjector pr) {
    final cy = pr.cy, sy = pr.sy, cp = pr.cp, sp = pr.sp;
    final h = model.height;
    final quads = <_Quad>[];
    for (final c in geo.copies) {
      final cnt = c.s * _n;
      for (var k = 0; k < cnt; k++) {
        final px = c.pos[k * 3];
        final py = c.pos[k * 3 + 1] - h * 0.5;
        final pz = c.pos[k * 3 + 2];
        final x1 = px * cy + pz * sy;
        final z1 = -px * sy + pz * cy;
        final y2 = py * cp - z1 * sp;
        final z2 = py * sp + z1 * cp;
        final kk = pr.base * pr.d / (pr.d - z2);
        c.sx[k] = pr.size.width / 2 + pr.ox + x1 * kk;
        c.sy[k] = pr.size.height / 2 - y2 * kk;
        c.sz[k] = z2;
        final nx = c.nor[k * 2];
        final nz = c.nor[k * 2 + 1];
        final nz1 = -nx * sy + nz * cy;
        final nx1 = nx * cy + nz * sy;
        final ny2 = -nz1 * sp;
        c.nz2[k] = nz1 * cp;
        c.lam[k] = (-0.4 * nx1 + 0.5 * ny2 + 0.75 * nz1).clamp(0.0, 1.0).toDouble();
      }
      for (var i = 0; i < c.s - 1; i++) {
        for (var j = 0; j < _n; j++) {
          final j1 = (j + 1) % _n;
          final a = i * _n + j;
          final b = i * _n + j1;
          if ((c.nz2[a] + c.nz2[b]) / 2 < -0.02) continue;
          final e = (i + 1) * _n + j1;
          final f = (i + 1) * _n + j;
          quads.add(_Quad(c, i, j, (c.sz[a] + c.sz[b] + c.sz[e] + c.sz[f]) / 4));
        }
      }
    }
    quads.sort((u, v) => u.z.compareTo(v.z));

    final pos = Float32List(quads.length * 12);
    final col = Int32List(quads.length * 6);
    var pi = 0;
    var ci = 0;
    for (final q in quads) {
      final c = q.c;
      final j1 = (q.j + 1) % _n;
      final a = q.i * _n + q.j;
      final b = q.i * _n + j1;
      final e = (q.i + 1) * _n + j1;
      final f = (q.i + 1) * _n + q.j;
      final sh = 0.45 + 0.55 * c.lam[a];
      final r = (c.rgb[q.i * 3] * sh).round().clamp(0, 255);
      final g = (c.rgb[q.i * 3 + 1] * sh).round().clamp(0, 255);
      final bl = (c.rgb[q.i * 3 + 2] * sh).round().clamp(0, 255);
      final argb = (0xFF << 24) | (r << 16) | (g << 8) | bl;
      for (final v in [a, b, e, a, e, f]) {
        pos[pi++] = c.sx[v];
        pos[pi++] = c.sy[v];
        col[ci++] = argb;
      }
    }
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: col);
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint());
    vertices.dispose();
  }

  void _drawHeart(Canvas canvas, TwinProjector pr) {
    final c = model.heartCenter;
    final pu = _pulse();
    final p = pr.project(c.x, c.y, c.z + 6);
    final col = _sevColor('heart');
    canvas.drawCircle(p, 7 + 6 * pu, Paint()..color = col.withOpacity(0.25));
    canvas.drawCircle(p, 4.5 + 2.5 * pu, Paint()..color = col);
  }

  void _drawLabels(Canvas canvas, Size size, TwinProjector pr) {
    final a = anchors(pr);
    final entries = a.entries.toList()..sort((x, y) => x.value.dy.compareTo(y.value.dy));
    var lastY = -100.0;
    for (final e in entries) {
      final text = labels[e.key];
      if (text == null) continue;
      var y = e.value.dy;
      final gap = kIsWeb ? 21.0 : 17.0;
      if (y - lastY < gap) y = lastY + gap;
      lastY = y;
      final color = _sevColor(e.key);
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFFE8EEF3), fontSize: kIsWeb ? 15 : 12, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = math.min(size.width - tp.width - 6, math.max(e.value.dx + 16, size.width * 0.64));
      final lp = Paint()
        ..color = color.withOpacity(0.8)
        ..strokeWidth = 0.9;
      canvas.drawLine(e.value, Offset(x - 4, y), lp);
      canvas.drawCircle(e.value, 3, Paint()..color = color);
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pr = TwinProjector(yaw, zoom, size, model.height);
    _drawGround(canvas, pr);
    if (previous != null) _drawGhost(canvas, pr, previous!);
    _drawMesh(canvas, pr);
    _drawHeart(canvas, pr);
    _drawLabels(canvas, size, pr);
  }

  /// Distretto sotto il tocco, se c'e'.
  String? hit(Offset p, Size size) {
    final pr = TwinProjector(yaw, zoom, size, model.height);
    String? best;
    var bestD = 36.0;
    for (final part in model.parts) {
      for (final r in part.rings) {
        if (!r.measured || r.tag == null) continue;
        for (final mirror in part.mirrored ? const [false, true] : const [false]) {
          for (var j = 0; j < _n; j++) {
            final v = r.vertex(j, mirror: mirror);
            final d = (pr.project(v.x, v.y, v.z) - p).distance;
            if (d < bestD) {
              bestD = d;
              best = r.tag;
            }
          }
        }
      }
    }
    final hc = model.heartCenter;
    if ((pr.project(hc.x, hc.y, hc.z) - p).distance < bestD) best = 'heart';
    return best;
  }

  @override
  bool shouldRepaint(covariant TwinPainter old) => true;
}

class TwinView extends StatefulWidget {
  final BodyModel model;
  final BodyModel? previous;
  final Map<String, Severity> severity;
  final Map<String, String> labels;
  final double heartRate;
  final void Function(String tag)? onTapPart;

  const TwinView({
    super.key,
    required this.model,
    required this.severity,
    required this.labels,
    required this.heartRate,
    this.previous,
    this.onTapPart,
  });

  @override
  State<TwinView> createState() => _TwinViewState();
}

class _TwinViewState extends State<TwinView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late TwinGeometry _geo;
  double _t = 0;
  double _yaw = 0.5;
  double _zoom = 1.0;
  double _zoomStart = 1.0;
  bool _auto = true;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _geo = TwinGeometry(widget.model, widget.severity);
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      setState(() {
        _t = elapsed.inMicroseconds / 1e6;
        if (_auto) _yaw += dt * 0.35;
      });
    })..start();
  }

  @override
  void didUpdateWidget(covariant TwinView old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model || old.severity != widget.severity) {
      _geo = TwinGeometry(widget.model, widget.severity);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  TwinPainter _painter() => TwinPainter(
        geo: _geo,
        previous: widget.previous,
        severity: widget.severity,
        labels: widget.labels,
        yaw: _yaw,
        zoom: _zoom,
        time: _t,
        heartRate: widget.heartRate,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return Stack(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            _zoomStart = _zoom;
            _auto = false;
          },
          onScaleUpdate: (d) {
            setState(() {
              _yaw += d.focalPointDelta.dx * 0.012;
              _zoom = (_zoomStart * d.scale).clamp(0.6, 3.0).toDouble();
            });
          },
          onTapUp: (d) {
            final tag = _painter().hit(d.localPosition, size);
            if (tag != null) widget.onTapPart?.call(tag);
          },
          child: CustomPaint(size: size, painter: _painter()),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: IconButton(
            tooltip: _auto ? 'Ferma la rotazione' : 'Ruota da sola',
            onPressed: () => setState(() => _auto = !_auto),
            icon: Icon(_auto ? Icons.pause_circle_outline : Icons.play_circle_outline),
          ),
        ),
      ]);
    });
  }
}
