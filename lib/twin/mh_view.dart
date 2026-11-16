/// Vista 3D del corpo MakeHuman: mappa a colori su mesh reale.
///
/// Una sola chiamata drawVertices; i triangoli rivolti al visore sono ordinati
/// per profondita' (counting sort), i colori sfumano sui vertici.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/models.dart';
import '../ui/theme.dart';
import 'mh_body.dart';
import 'twin_view.dart' show TwinProjector;

const int _buckets = 2048;

class _Buf {
  final int nv;
  final int nt;
  final Float32List sx;
  final Float32List sy;
  final Float32List sz;
  final Float32List lam;
  final Float32List pos2;
  final Int32List col;
  final Uint16List idx;
  final Int32List cnt = Int32List(_buckets + 2);
  final Int32List bucket;
  final Uint8List front;

  _Buf(this.nv, this.nt)
      : sx = Float32List(nv),
        sy = Float32List(nv),
        sz = Float32List(nv),
        lam = Float32List(nv),
        pos2 = Float32List(nv * 2),
        col = Int32List(nv),
        idx = Uint16List(nt * 3),
        bucket = Int32List(nt),
        front = Uint8List(nt);
}

class MhPainter extends CustomPainter {
  final MhBody body;
  final MhBody? previous;
  final Float32List rgb;
  final _Buf buf;
  final Map<String, Color> colors;
  final Map<String, String> labels;
  final double yaw;
  final double zoom;
  final double time;
  final double heartRate;

  MhPainter({
    required this.body,
    required this.previous,
    required this.rgb,
    required this.buf,
    required this.colors,
    required this.labels,
    required this.yaw,
    required this.zoom,
    required this.time,
    required this.heartRate,
  });

  Color _sevColor(String key) => colors[key] ?? kWireColor;

  double _pulse() {
    var period = 60.0 / math.max(30.0, heartRate);
    period = period.clamp(0.35, 2.0).toDouble();
    final phase = (time / period) % 1.0;
    if (phase < 0.15) return math.sin(phase / 0.15 * math.pi);
    if (phase < 0.30) return 0.35 * math.sin((phase - 0.15) / 0.15 * math.pi);
    return 0.0;
  }

  Map<String, Offset> anchors(TwinProjector pr) {
    final out = <String, Offset>{};
    body.rings.forEach((tag, polys) {
      Offset? best;
      for (final p in polys) {
        for (var i = 0; i < p.length; i += 3) {
          final o = pr.project(p[i], p[i + 1], p[i + 2]);
          if (best == null || o.dx > best.dx) best = o;
        }
      }
      if (best != null) out[tag] = best;
    });
    final c = body.heart;
    out['heart'] = pr.project(c[0], c[1], c[2]);
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
  void _drawGhost(Canvas canvas, TwinProjector pr, MhBody prev) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = kGhostColor.withOpacity(0.7);
    prev.rings.forEach((tag, polys) {
      for (final p in polys) {
        final path = Path();
        for (var i = 0; i < p.length; i += 3) {
          final o = pr.project(p[i], p[i + 1], p[i + 2]);
          i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    });
  }

  void _drawMesh(Canvas canvas, TwinProjector pr) {
    final cy = pr.cy, sy = pr.sy, cp = pr.cp, sp = pr.sp;
    final h = body.height;
    final nv = buf.nv;
    final pos = body.pos, nor = body.nor;
    final w2 = pr.size.width / 2 + pr.ox, h2 = pr.size.height / 2;
    final bd = pr.base * pr.d;
    final dd = pr.d;
    var zmin = double.infinity, zmax = -double.infinity;
    for (var v = 0; v < nv; v++) {
      final px = pos[v * 3];
      final py = pos[v * 3 + 1] - h * 0.5;
      final pz = pos[v * 3 + 2];
      final x1 = px * cy + pz * sy;
      final z1 = -px * sy + pz * cy;
      final y2 = py * cp - z1 * sp;
      final z2 = py * sp + z1 * cp;
      final k = bd / (dd - z2);
      buf.sx[v] = w2 + x1 * k;
      buf.sy[v] = h2 - y2 * k;
      buf.sz[v] = z2;
      if (z2 < zmin) zmin = z2;
      if (z2 > zmax) zmax = z2;
      final nx = nor[v * 3], ny = nor[v * 3 + 1], nz = nor[v * 3 + 2];
      final nx1 = nx * cy + nz * sy;
      final nz1 = -nx * sy + nz * cy;
      final ny2 = ny * cp - nz1 * sp;
      final nz2 = ny * sp + nz1 * cp;
      final l = -0.4 * nx1 + 0.5 * ny2 + 0.75 * nz2;
      buf.lam[v] = l < 0 ? 0 : (l > 1 ? 1 : l);
    }
    final range = zmax - zmin;
    final scale = range > 0 ? (_buckets - 1) / range : 0.0;
    final tris = body.data.tris;
    final nt = buf.nt;
    buf.cnt.fillRange(0, buf.cnt.length, 0);
    for (var t = 0; t < nt; t++) {
      final a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
      final ax = buf.sx[a], ay = buf.sy[a];
      final area = (buf.sx[b] - ax) * (buf.sy[c] - ay) - (buf.sy[b] - ay) * (buf.sx[c] - ax);
      if (area < 0) {
        buf.front[t] = 1;
        final z = (buf.sz[a] + buf.sz[b] + buf.sz[c]) / 3;
        final bk = ((z - zmin) * scale).toInt();
        buf.bucket[t] = bk;
        buf.cnt[bk + 1]++;
      } else {
        buf.front[t] = 0;
      }
    }
    for (var i = 1; i < buf.cnt.length; i++) {
      buf.cnt[i] += buf.cnt[i - 1];
    }
    final total = buf.cnt[_buckets];
    for (var t = 0; t < nt; t++) {
      if (buf.front[t] == 0) continue;
      final o = buf.cnt[buf.bucket[t]]++;
      buf.idx[o * 3] = tris[t * 3];
      buf.idx[o * 3 + 1] = tris[t * 3 + 1];
      buf.idx[o * 3 + 2] = tris[t * 3 + 2];
    }
    for (var v = 0; v < nv; v++) {
      buf.pos2[v * 2] = buf.sx[v];
      buf.pos2[v * 2 + 1] = buf.sy[v];
      final sh = 0.45 + 0.55 * buf.lam[v];
      final r = (rgb[v * 3] * sh).round().clamp(0, 255);
      final g = (rgb[v * 3 + 1] * sh).round().clamp(0, 255);
      final b = (rgb[v * 3 + 2] * sh).round().clamp(0, 255);
      buf.col[v] = (0xFF << 24) | (r << 16) | (g << 8) | b;
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      buf.pos2,
      colors: buf.col,
      indices: Uint16List.sublistView(buf.idx, 0, total * 3),
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint());
    vertices.dispose();
  }

  void _drawHeart(Canvas canvas, TwinProjector pr) {
    if (pr.cy < 0.05) return; // di schiena il cuore non si vede
    final c = body.heart;
    final pu = _pulse();
    final p = pr.project(c[0], c[1], c[2]);
    final col = _sevColor('heart');
    // Alone: sfumatura radiale che si accende e si allarga a ogni battito
    // (ritmo = frequenza misurata). Somma di luce, cosi' si vede anche sopra
    // un torace gia' colorato.
    final r = pr.base * (4.0 + 3.0 * pu);
    final halo = Paint()
      ..shader = ui.Gradient.radial(p, r, [col.withOpacity(0.55 + 0.35 * pu), col.withOpacity(0.0)])
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(p, r, halo);
    canvas.drawCircle(p, 3.0 + 2.0 * pu, Paint()..color = col);
  }

  void _drawLabels(Canvas canvas, Size size, TwinProjector pr) {
    final a = anchors(pr);
    final entries = a.entries.toList()..sort((x, y) => x.value.dy.compareTo(y.value.dy));
    var lastY = -100.0;
    final sc = kIsWeb ? kLabelScale : 1.0;
    for (final e in entries) {
      final text = labels[e.key];
      if (text == null) continue;
      var y = e.value.dy;
      final gap = 17.0 * sc;
      if (y - lastY < gap) y = lastY + gap;
      lastY = y;
      final color = _sevColor(e.key);
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(color: const Color(0xFFE8EEF3), fontSize: 12 * sc, fontWeight: FontWeight.w600)),
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
    final pr = TwinProjector(yaw, zoom, size, body.height);
    _drawGround(canvas, pr);
    if (previous != null) _drawGhost(canvas, pr, previous!);
    _drawMesh(canvas, pr);
    _drawHeart(canvas, pr);
    _drawLabels(canvas, size, pr);
  }

  String? hit(Offset p, Size size) {
    final pr = TwinProjector(yaw, zoom, size, body.height);
    String? best;
    var bestD = 36.0;
    body.rings.forEach((tag, polys) {
      for (final poly in polys) {
        for (var i = 0; i < poly.length; i += 3) {
          final d = (pr.project(poly[i], poly[i + 1], poly[i + 2]) - p).distance;
          if (d < bestD) {
            bestD = d;
            best = tag;
          }
        }
      }
    });
    final hc = body.heart;
    if ((pr.project(hc[0], hc[1], hc[2]) - p).distance < bestD) best = 'heart';
    return best;
  }

  @override
  bool shouldRepaint(covariant MhPainter old) => true;
}

class MhTwinView extends StatefulWidget {
  final MhBody body;
  final MhBody? previous;
  final Map<String, Color> colors;
  final Map<String, String> labels;
  final double heartRate;
  final void Function(String tag)? onTapPart;

  const MhTwinView({
    super.key,
    required this.body,
    required this.colors,
    required this.labels,
    required this.heartRate,
    this.previous,
    this.onTapPart,
  });

  @override
  State<MhTwinView> createState() => _MhTwinViewState();
}

class _MhTwinViewState extends State<MhTwinView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late Float32List _rgb;
  late _Buf _buf;
  double _t = 0;
  double _yaw = 0.5;
  double _zoom = 1.0;
  double _zoomStart = 1.0;
  bool _auto = true;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _prepare();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      setState(() {
        _t = elapsed.inMicroseconds / 1e6;
        if (_auto) _yaw += dt * 0.35;
      });
    })..start();
  }

  void _prepare() {
    _rgb = widget.body.regionRgb(widget.colors);
    _buf = _Buf(widget.body.data.nv, widget.body.data.tris.length ~/ 3);
  }

  @override
  void didUpdateWidget(covariant MhTwinView old) {
    super.didUpdateWidget(old);
    if (old.body != widget.body || old.colors != widget.colors) _prepare();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  MhPainter _painter() => MhPainter(
        body: widget.body,
        previous: widget.previous,
        rgb: _rgb,
        buf: _buf,
        colors: widget.colors,
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
