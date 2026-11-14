/// Dati del corpo MakeHuman (CC0) convertiti da tools/bake_mh.py.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Spostamenti per vertice di un target MakeHuman (unita': decimetri).
class MhTarget {
  final Uint16List idx;
  final Float32List d;
  const MhTarget(this.idx, this.d);
}

class MhData {
  final int nv;
  final Float32List base;
  final Uint16List tris;
  final List<double> wristAxis;
  final Map<String, MhTarget> targets;

  const MhData(this.nv, this.base, this.tris, this.wristAxis, this.targets);

  static Future<MhData>? _shared;

  /// Carica una sola volta i dati (asset) e li riusa.
  static Future<MhData> shared() => _shared ??= load();

  static Future<MhData> load() async {
    final bd = await rootBundle.load('assets/mh/body.bin');
    return parse(bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes));
  }

  static MhData parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    var o = 0;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'MHB1') {
      throw const FormatException('body.bin non valido');
    }
    o = 4;
    final nv = bd.getUint32(o, Endian.little);
    o += 4;
    final base = Float32List(nv * 3);
    for (var i = 0; i < nv * 3; i++, o += 4) {
      base[i] = bd.getFloat32(o, Endian.little);
    }
    final nt = bd.getUint32(o, Endian.little);
    o += 4;
    final tris = Uint16List(nt * 3);
    for (var i = 0; i < nt * 3; i++, o += 2) {
      tris[i] = bd.getUint16(o, Endian.little);
    }
    final axis = <double>[];
    for (var i = 0; i < 3; i++, o += 4) {
      axis.add(bd.getFloat32(o, Endian.little));
    }
    final n = bd.getUint32(o, Endian.little);
    o += 4;
    final targets = <String, MhTarget>{};
    for (var t = 0; t < n; t++) {
      final len = bd.getUint8(o);
      o += 1;
      final name = String.fromCharCodes(bytes.sublist(o, o + len));
      o += len;
      final c = bd.getUint32(o, Endian.little);
      o += 4;
      final idx = Uint16List(c);
      for (var i = 0; i < c; i++, o += 2) {
        idx[i] = bd.getUint16(o, Endian.little);
      }
      final d = Float32List(c * 3);
      for (var i = 0; i < c * 3; i++, o += 4) {
        d[i] = bd.getFloat32(o, Endian.little);
      }
      targets[name] = MhTarget(idx, d);
    }
    return MhData(nv, base, tris, axis, targets);
  }
}
