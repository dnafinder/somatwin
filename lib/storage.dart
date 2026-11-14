import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/absi_table.dart';
import 'core/models.dart';

class Record {
  final String id;
  final Measurements m;
  final Anamnesis an;

  const Record(this.id, this.m, this.an);

  Map<String, dynamic> toJson() => {'id': id, 'm': m.toJson(), 'an': an.toJson()};

  factory Record.fromJson(Map<String, dynamic> j) => Record(
        j['id'] as String,
        Measurements.fromJson(j['m'] as Map<String, dynamic>),
        Anamnesis.fromJson(j['an'] as Map<String, dynamic>),
      );
}

/// Storico locale (solo sul dispositivo). Piu' recente per primo.
class Storage {
  static const _key = 'records_v1';

  Future<List<Record>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => Record.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.m.takenOn.compareTo(a.m.takenOn));
    return list;
  }

  Future<void> _save(List<Record> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  Future<void> add(Record r) async {
    final list = await load();
    list.add(r);
    await _save(list);
  }

  /// Sostituisce una misura esistente (correzione di un errore di inserimento).
  Future<void> update(Record r) async {
    final list = await load();
    final i = list.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      list[i] = r;
    } else {
      list.add(r);
    }
    await _save(list);
  }

  Future<void> delete(String id) async {
    final list = await load();
    list.removeWhere((r) => r.id == id);
    await _save(list);
  }
}

Future<AbsiTable> loadAbsiTable() async {
  final m = await rootBundle.loadString('assets/absi_male.csv');
  final f = await rootBundle.loadString('assets/absi_female.csv');
  return AbsiTable.parse(m, f);
}
