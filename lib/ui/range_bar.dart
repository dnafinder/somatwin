import 'package:flutter/material.dart';

const Color kBarBlue = Color(0xFF00E5FF);
const Color kBarGreen = Color(0xFF3CB043);
const Color kBarRed = Color(0xFFD9534F);

/// Intervallo di riferimento letto dal testo: "a - b", "< x", "> x".
class RefRange {
  final double? lo;
  final double? hi;
  const RefRange(this.lo, this.hi);

  static final _num = r'(-?\d+(?:\.\d+)?)';
  static final _two = RegExp('^\\s*$_num\\s+-\\s+$_num\\s*\$');
  static final _lt = RegExp('^\\s*<\\s*$_num\\s*\$');
  static final _gt = RegExp('^\\s*>\\s*$_num\\s*\$');

  static RefRange? parse(String s) {
    var m = _two.firstMatch(s);
    if (m != null) {
      final a = double.parse(m.group(1)!), b = double.parse(m.group(2)!);
      if (b <= a) return null;
      // "0 - x" significa soltanto "sotto x".
      return RefRange(a == 0 ? null : a, b);
    }
    m = _lt.firstMatch(s);
    if (m != null) return RefRange(null, double.parse(m.group(1)!));
    m = _gt.firstMatch(s);
    if (m != null) return RefRange(double.parse(m.group(1)!), null);
    return null;
  }
}

/// Colore della zona in cui cade il valore, lo stesso della barra.
/// Null se la barra non c'e' (riferimento assente o valore non numerico).
Color? zoneColor(String reference, double? v) {
  final r = RefRange.parse(reference);
  if (v == null || r == null) return null;
  final lo = r.lo, hi = r.hi;
  if (lo != null && hi != null) return v < lo ? kBarBlue : (v <= hi ? kBarGreen : kBarRed);
  if (hi != null) return v <= hi ? kBarGreen : kBarRed;
  return v < lo! ? kBarRed : kBarGreen;
}

/// Barra a tre zone (blu sotto, verde nella norma, rosso sopra) con un
/// pallino sulla posizione del valore. Se la norma ha un solo limite
/// la zona opposta non esiste: per "< x" sotto e' verde, per "> x" sopra e' verde.
class RangeBar extends StatelessWidget {
  final String reference;
  final double? value;
  const RangeBar({super.key, required this.reference, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final r = RefRange.parse(reference);
    if (v == null || r == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 26,
        width: double.infinity,
        child: CustomPaint(painter: _BarPainter(r, v)),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final RefRange r;
  final double v;
  _BarPainter(this.r, this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final lo = r.lo, hi = r.hi;
    double a, b; // limiti dell'asse
    final zones = <(double, double, Color)>[]; // frazioni 0-1

    if (lo != null && hi != null) {
      final span = hi - lo;
      a = lo - span * 0.8;
      b = hi + span * 0.8;
    } else if (hi != null) {
      a = hi > 0 ? 0 : hi * 1.6;
      b = hi > 0 ? hi * 1.6 : 0;
    } else {
      a = lo! * 0.6;
      b = lo * 1.4;
      if (lo < 0) {
        a = lo * 1.4;
        b = lo * 0.6;
      }
    }
    // Il valore fuori scala resta sul bordo.
    if (v < a) a = v - (b - a) * 0.05;
    if (v > b) b = v + (b - a) * 0.05;
    double f(double x) => ((x - a) / (b - a)).clamp(0.0, 1.0);

    if (lo != null && hi != null) {
      zones
        ..add((0, f(lo), kBarBlue))
        ..add((f(lo), f(hi), kBarGreen))
        ..add((f(hi), 1, kBarRed));
    } else if (hi != null) {
      zones
        ..add((0, f(hi), kBarGreen))
        ..add((f(hi), 1, kBarRed));
    } else {
      zones
        ..add((0, f(lo!), kBarRed))
        ..add((f(lo), 1, kBarGreen));
    }

    const h = 14.0;
    final top = (size.height - h) / 2;
    final rect = Rect.fromLTWH(0, top, size.width, h);
    final track = RRect.fromRectAndRadius(rect, const Radius.circular(7));

    // Ombra sotto la barra, per staccarla dal fondo.
    canvas.drawRRect(track.shift(const Offset(0, 2)), Paint()..color = const Color(0x99000000));

    canvas.save();
    canvas.clipRRect(track);
    for (final z in zones) {
      canvas.drawRect(Rect.fromLTRB(z.$1 * size.width, top, z.$2 * size.width, top + h), Paint()..color = z.$3);
    }
    // Rilievo: luce in alto, ombra in basso.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66FFFFFF), Color(0x00FFFFFF), Color(0x55000000)],
          stops: [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
    // Stacco scuro fra le zone.
    for (var k = 1; k < zones.length; k++) {
      final xx = zones[k].$1 * size.width;
      canvas.drawRect(Rect.fromLTWH(xx - 1, top, 2, h), Paint()..color = const Color(0xFF0B1620));
    }
    canvas.restore();
    canvas.drawRRect(
        track,
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    final x = (f(v) * size.width).clamp(10.0, size.width - 10.0);
    final c = Offset(x, size.height / 2);
    canvas.drawCircle(c.translate(0, 1.5), 10, Paint()..color = const Color(0x99000000));
    canvas.drawCircle(c, 10, Paint()..color = Colors.white);
    canvas.drawCircle(
        c,
        10,
        Paint()
          ..color = const Color(0xFF0B1620)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.r != r || o.v != v;
}
