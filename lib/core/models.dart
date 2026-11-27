/// Modelli di dominio: input, esiti e livelli di gravita'.
library;

enum Sex { male, female }

extension SexX on Sex {
  /// Codifica degli script MATLAB: 0 = maschio, 1 = femmina.
  int get code => this == Sex.male ? 0 : 1;
  String get label => this == Sex.male ? 'Maschio' : 'Femmina';
}

/// Livello di attenzione di un esito. Colori nella UI (palette daltonica).
enum Severity { ok, watch, alert, info }

Severity worst(Severity a, Severity b) {
  if (a == Severity.alert || b == Severity.alert) return Severity.alert;
  if (a == Severity.watch || b == Severity.watch) return Severity.watch;
  if (a == Severity.ok || b == Severity.ok) return Severity.ok;
  return Severity.info;
}

/// Misure del soggetto. Unita': kg, cm, mmHg, bpm.
class Measurements {
  final Sex sex;
  final DateTime birthDate;
  final DateTime takenOn;
  final double weight;
  final double height;
  final double waist;
  final double hip;
  final double wrist;
  final double neck;
  final double calf;
  final double sbp;
  final double dbp;
  final double hr;

  const Measurements({
    required this.sex,
    required this.birthDate,
    required this.takenOn,
    required this.weight,
    required this.height,
    required this.waist,
    required this.hip,
    required this.wrist,
    required this.neck,
    required this.calf,
    required this.sbp,
    required this.dbp,
    required this.hr,
  });

  /// Stessa misura con sesso e data di nascita del registro.
  Measurements withIdentity(Sex s, DateTime birth) => Measurements(
        sex: s,
        birthDate: birth,
        takenOn: takenOn,
        weight: weight,
        height: height,
        waist: waist,
        hip: hip,
        wrist: wrist,
        neck: neck,
        calf: calf,
        sbp: sbp,
        dbp: dbp,
        hr: hr,
      );

  /// Eta' in anni compiuti alla data della misurazione.
  int get age {
    var a = takenOn.year - birthDate.year;
    if (takenOn.month < birthDate.month ||
        (takenOn.month == birthDate.month && takenOn.day < birthDate.day)) {
      a--;
    }
    return a;
  }

  Map<String, dynamic> toJson() => {
        'sex': sex.code,
        'birth': birthDate.toIso8601String(),
        'on': takenOn.toIso8601String(),
        'weight': weight,
        'height': height,
        'waist': waist,
        'hip': hip,
        'wrist': wrist,
        'neck': neck,
        'calf': calf,
        'sbp': sbp,
        'dbp': dbp,
        'hr': hr,
      };

  factory Measurements.fromJson(Map<String, dynamic> j) => Measurements(
        sex: (j['sex'] as num).toInt() == 0 ? Sex.male : Sex.female,
        birthDate: DateTime.parse(j['birth'] as String),
        takenOn: DateTime.parse(j['on'] as String),
        weight: (j['weight'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        waist: (j['waist'] as num).toDouble(),
        hip: (j['hip'] as num).toDouble(),
        wrist: (j['wrist'] as num).toDouble(),
        neck: (j['neck'] as num).toDouble(),
        calf: (j['calf'] as num).toDouble(),
        sbp: (j['sbp'] as num).toDouble(),
        dbp: (j['dbp'] as num).toDouble(),
        hr: (j['hr'] as num).toDouble(),
      );
}

/// Anamnesi facoltativa. Serve solo al rischio di ipertensione.
class Anamnesis {
  final bool answered;
  final bool smoker;

  /// Genitori ipertesi: 0, 1 o 2.
  final int parentsHypertensive;
  final bool onAntihypertensives;

  /// Questionario STOP-BANG compilato. Le voci che le misure non danno:
  /// russamento forte, stanchezza diurna, apnee osservate, ipertensione
  /// diagnosticata (anche senza terapia).
  final bool stopBangAnswered;
  final bool snoring;
  final bool tired;
  final bool observedApnea;
  final bool hypertensionDiagnosed;

  const Anamnesis({
    this.answered = false,
    this.smoker = false,
    this.parentsHypertensive = 0,
    this.onAntihypertensives = false,
    this.stopBangAnswered = false,
    this.snoring = false,
    this.tired = false,
    this.observedApnea = false,
    this.hypertensionDiagnosed = false,
  });

  Map<String, dynamic> toJson() => {
        'answered': answered,
        'smoker': smoker,
        'php': parentsHypertensive,
        'hp': onAntihypertensives,
        'sba': stopBangAnswered,
        'snr': snoring,
        'tir': tired,
        'apn': observedApnea,
        'htd': hypertensionDiagnosed,
      };

  factory Anamnesis.fromJson(Map<String, dynamic> j) => Anamnesis(
        answered: j['answered'] as bool,
        smoker: j['smoker'] as bool,
        parentsHypertensive: (j['php'] as num).toInt(),
        onAntihypertensives: j['hp'] as bool,
        // Salvataggi precedenti non hanno il questionario.
        stopBangAnswered: j['sba'] as bool? ?? false,
        snoring: j['snr'] as bool? ?? false,
        tired: j['tir'] as bool? ?? false,
        observedApnea: j['apn'] as bool? ?? false,
        hypertensionDiagnosed: j['htd'] as bool? ?? false,
      );
}

/// Una riga del referto.
class IndexResult {
  final String group;
  final String key;
  final String label;
  final String value;
  final String unit;
  final String reference;
  final String comment;
  final Severity severity;

  /// Soglie crescenti di una scala a gradi (3 soglie = 4 zone, dalla migliore
  /// alla peggiore). Vuoto per gli indici con un intervallo di riferimento.
  final List<double> grades;

  const IndexResult({
    required this.group,
    required this.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.reference = '',
    this.comment = '',
    this.severity = Severity.info,
    this.grades = const [],
  });
}

class HrZone {
  final String label;
  final String range;
  const HrZone(this.label, this.range);
}

class Report {
  final int age;
  final List<IndexResult> results;

  /// Valori numerici per chiave (test e modello 3D).
  final Map<String, double> values;

  /// Gravita' per distretto corporeo: waist, hip, neck, calf, wrist, heart.
  final Map<String, Severity> body;
  final List<HrZone> zonesFcmax;
  final List<HrZone> zonesKarvonen;
  final List<String> notes;

  const Report({
    required this.age,
    required this.results,
    required this.values,
    required this.body,
    required this.zonesFcmax,
    required this.zonesKarvonen,
    required this.notes,
  });

  IndexResult? byKey(String key) {
    for (final r in results) {
      if (r.key == key) return r;
    }
    return null;
  }
}
