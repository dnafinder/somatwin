/// Tabella ABSI (Krakauer & Krakauer 2012, NHANES 1999-2004), media e DS per eta' e sesso.
/// File CSV: eta',media,DS; righe per eta' 2..85.
library;

import 'models.dart';

class AbsiRef {
  final double mean;
  final double sd;
  const AbsiRef(this.mean, this.sd);
}

class AbsiTable {
  final List<AbsiRef> _male;
  final List<AbsiRef> _female;

  AbsiTable._(this._male, this._female);

  factory AbsiTable.parse(String maleCsv, String femaleCsv) =>
      AbsiTable._(_parse(maleCsv), _parse(femaleCsv));

  static List<AbsiRef> _parse(String csv) {
    final out = <AbsiRef>[];
    for (final line in csv.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final p = t.split(',');
      out.add(AbsiRef(double.parse(p[1]), double.parse(p[2])));
    }
    return out;
  }

  AbsiRef lookup(int age, Sex sex) {
    final list = sex == Sex.male ? _male : _female;
    var i = age;
    if (i < 2) i = 2;
    if (i > 85) i = 85;
    return list[i - 2];
  }
}
