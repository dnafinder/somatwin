/// Vista 3D wireframe del digital twin: proiezione prospettica su Canvas,
/// rotazione e zoom a dito, cuore che batte alla frequenza misurata.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/models.dart';
import '../ui/theme.dart';
import 'body_model.dart';

class _P {
  final Offset o;
  final double z;
  const _P(this.o, this.z);
}

/// Proiezione condivisa da disegno e hit-test.
class TwinProjector {
  final double yaw;
  final double pitch;
  final double zoom;
  final Size size;
  final double height;

  const TwinProjector(this.yaw, this.pitch, this.zoom, this.size, this.height);

  _P project(Vec3 p) {
    final px = p.x;
    final py = p.y - height * 0.5;
    final pz = p.z;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final x1 = px * cy + pz * sy;
    final z1 = -px * sy + pz * cy;
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final y2 = py * cp - z1 * sp;
    final z2 = py * sp + z1 * cp;
    final d = height * 2.6;
    final persp = d / (d - z2);
    final base = math.min(size.height * 0.90 / height, size.width * 0.80 / (height * 0.5));
    final k = base * zoom * persp;
    return _P(Offset(size.width / 2 + x1 * k, size.height / 2 - y2 * k), z2);
  }
}

class TwinPainter extends CustomPainter {
  final BodyModel model;
  final BodyModel? previous;
  final Map<String, Severity> severity;
  final Map<String, String> labels;
  final double yaw;
  final double pitch;
  final double zoom;
  final double time;
  final double heartRate;

  TwinPainter({
    required this.model,
    required this.previous,
    required this.severity,
    required this.labels,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.time,
    required this.heartRate,
  });

  Color _tagColor(String? tag) {
    final s = severity[tag];
    return s == null ? kWireColor : sevColor(s);
  }

  double _alpha(double z) {
    final t = (z / (model.height * 0.25)).clamp(-1.0, 1.0).toDouble();
    return 0.55 + 0.45 * (t + 1) / 2;
  }

  void _drawModel(Canvas canvas, TwinProjector pr, BodyModel mdl,
      {required bool ghost}) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final part in mdl.parts) {
      final copies = part.mirrored ? const [false, true] : const [false];
      for (final mirror in copies) {
        // Sezioni
        final pts = <List<_P>>[];
        for (final r in part.rings) {
          final ring = <_P>[];
          for (var j = 0; j < kRingPoints; j++) {
            ring.add(pr.project(r.vertex(j, mirror: mirror)));
          }
          pts.add(ring);
        }
        for (var i = 0; i < part.rings.length; i++) {
          final r = part.rings[i];
          final ring = pts[i];
          final measured = r.measured && !ghost;
          final base = ghost ? kGhostColor : (measured ? _tagColor(r.tag) : kWireColor);
          line.strokeWidth = measured ? 2.6 : 1.0;
          for (var j = 0; j < kRingPoints; j++) {
            // gli anelli stimati sono tratteggiati
            if (!r.measured && j.isOdd) continue;
            final p0 = ring[j];
            final p1 = ring[(j + 1) % kRingPoints];
            final a = ghost ? 0.45 : _alpha((p0.z + p1.z) / 2);
            line.color = base.withOpacity(measured ? math.min(1.0, a + 0.2) : a * 0.85);
            canvas.drawLine(p0.o, p1.o, line);
          }
        }
        // Linee longitudinali
        line.strokeWidth = 0.6;
        for (var i = 0; i + 1 < part.rings.length; i++) {
          for (var j = 0; j < kRingPoints; j += 3) {
            final p0 = pts[i][j];
            final p1 = pts[i + 1][j];
            final a = ghost ? 0.3 : _alpha((p0.z + p1.z) / 2) * 0.55;
            line.color = (ghost ? kGhostColor : kWireColor).withOpacity(a);
            canvas.drawLine(p0.o, p1.o, line);
          }
        }
      }
    }
  }

  /// Punto del cuore pulsante.
  double _pulse() {
    var period = 60.0 / math.max(30.0, heartRate);
    period = period.clamp(0.35, 2.0).toDouble();
    final phase = (time / period) % 1.0;
    if (phase < 0.15) return math.sin(phase / 0.15 * math.pi);
    if (phase < 0.30) return 0.35 * math.sin((phase - 0.15) / 0.15 * math.pi);
    return 0.0;
  }

  void _drawHeart(Canvas canvas, TwinProjector pr) {
    final c = model.heartCenter;
    final k = 0.33 * (1 + 0.18 * _pulse()) * (model.height / 175.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = sevColor(severity['heart'] ?? Severity.info);
    const slices = [-0.8, -0.4, 0.0, 0.4, 0.8];
    for (final zi in slices) {
      final f = math.sqrt(1 - zi * zi);
      Offset? prev;
      Offset? first;
      for (var i = 0; i <= 30; i++) {
        final t = 2 * math.pi * i / 30;
        final hx = 16 * math.pow(math.sin(t), 3).toDouble();
        final hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
        final p = pr.project(Vec3(c.x + hx * k * f, c.y + hy * k * f, c.z + zi * 3.5 * k * 3));
        if (prev != null) canvas.drawLine(prev, p.o, paint);
        first ??= p.o;
        prev = p.o;
      }
      if (first != null && prev != null) canvas.drawLine(prev, first, paint);
    }
  }

  /// Ancoraggi delle etichette: punto del bordo piu' a destra dello schermo.
  Map<String, Offset> anchors(TwinProjector pr) {
    final out = <String, Offset>{};
    for (final part in model.parts) {
      for (final r in part.rings) {
        if (!r.measured || r.tag == null) continue;
        Offset? best;
        for (final mirror in part.mirrored ? const [false, true] : const [false]) {
          for (var j = 0; j < kRingPoints; j++) {
            final p = pr.project(r.vertex(j, mirror: mirror)).o;
            if (best == null || p.dx > best.dx) best = p;
          }
        }
        if (best != null) out[r.tag!] = best;
      }
    }
    final h = pr.project(model.heartCenter).o;
    out['heart'] = h;
    return out;
  }

  void _drawLabels(Canvas canvas, Size size, TwinProjector pr) {
    final a = anchors(pr);
    final entries = a.entries.toList()..sort((x, y) => x.value.dy.compareTo(y.value.dy));
    var lastY = -100.0;
    for (final e in entries) {
      final text = labels[e.key];
      if (text == null) continue;
      var y = e.value.dy;
      if (y - lastY < 16) y = lastY + 16;
      lastY = y;
      final color = _tagColor(e.key);
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = math.min(size.width - tp.width - 6, math.max(e.value.dx + 14, size.width * 0.64));
      final lp = Paint()
        ..color = color.withOpacity(0.7)
        ..strokeWidth = 0.8;
      canvas.drawLine(e.value, Offset(x - 3, y), lp);
      canvas.drawCircle(e.value, 2.5, Paint()..color = color);
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pr = TwinProjector(yaw, pitch, zoom, size, model.height);
    // suolo
    final ground = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = kWireColor.withOpacity(0.18);
    for (final rad in [28.0, 52.0]) {
      Offset? prev;
      Offset? first;
      for (var i = 0; i <= 48; i++) {
        final t = 2 * math.pi * i / 48;
        final p = pr.project(Vec3(rad * math.cos(t), 0, rad * math.sin(t))).o;
        if (prev != null) canvas.drawLine(prev, p, ground);
        first ??= p;
        prev = p;
      }
    }
    if (previous != null) {
      _drawModel(canvas, pr, previous!, ghost: true);
    }
    _drawModel(canvas, pr, model, ghost: false);
    _drawHeart(canvas, pr);
    _drawLabels(canvas, size, pr);
  }

  /// Distretto sotto il tocco, se c'e'.
  String? hit(Offset p, Size size) {
    final pr = TwinProjector(yaw, pitch, zoom, size, model.height);
    String? best;
    var bestD = 30.0;
    for (final part in model.parts) {
      for (final r in part.rings) {
        if (!r.measured || r.tag == null) continue;
        for (final mirror in part.mirrored ? const [false, true] : const [false]) {
          for (var j = 0; j < kRingPoints; j++) {
            final d = (pr.project(r.vertex(j, mirror: mirror)).o - p).distance;
            if (d < bestD) {
              bestD = d;
              best = r.tag;
            }
          }
        }
      }
    }
    final dh = (pr.project(model.heartCenter).o - p).distance;
    if (dh < bestD) best = 'heart';
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
  double _t = 0;
  double _yaw = 0.5;
  double _pitch = 0.08;
  double _zoom = 1.0;
  double _zoomStart = 1.0;
  bool _auto = true;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  TwinPainter _painter() => TwinPainter(
        model: widget.model,
        previous: widget.previous,
        severity: widget.severity,
        labels: widget.labels,
        yaw: _yaw,
        pitch: _pitch,
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
              _yaw += d.focalPointDelta.dx * 0.01;
              _pitch = (_pitch - d.focalPointDelta.dy * 0.006).clamp(-0.6, 0.9).toDouble();
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
