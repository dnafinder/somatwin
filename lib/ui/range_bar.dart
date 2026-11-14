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
        height: 16,
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

    const h = 8.0;
    final top = (size.height - h) / 2;
    final track = RRect.fromRectAndRadius(Rect.fromLTWH(0, top, size.width, h), const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(track);
    for (final z in zones) {
      canvas.drawRect(Rect.fromLTRB(z.$1 * size.width, top, z.$2 * size.width, top + h), Paint()..color = z.$3);
    }
    canvas.restore();

    final x = (f(v) * size.width).clamp(7.0, size.width - 7.0);
    final c = Offset(x, size.height / 2);
    canvas.drawCircle(c, 7, Paint()..color = Colors.white);
    canvas.drawCircle(c, 7, Paint()
      ..color = const Color(0xFF0B1620)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.r != r || o.v != v;
}
