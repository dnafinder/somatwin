/// Calcolo degli indici. Port degli script MATLAB (BMIfun, BSAfun, BMR, BEE,
/// GrantIndex, cardiofun, parti antropometriche di cardiometx) piu' indici nuovi.
///
/// Correzioni rispetto agli script:
///  - AVI usa (waist - hip)^2 (lo script aveva waist - hip^2).
///  - Le classi con soglie sono continue (nessun "buco" tra un intervallo e il successivo).
library;

import 'dart:math' as math;

import 'absi_table.dart';
import 'models.dart';

/// Arrotondamento MATLAB: mezzo punto verso l'esterno (lontano da zero).
double mround(double x, [int digits = 0]) {
  final f = math.pow(10, digits).toDouble();
  final v = (x.abs() * f + 0.5).floorToDouble() / f;
  return x < 0 ? -v : v;
}

double _log10(double x) => math.log(x) / math.ln10;

double _pw(double base, double exp) => math.pow(base, exp).toDouble();

/// Numero di soglie <= v: indice di classe 0..soglie.length.
int cls(double v, List<double> thresholds) {
  var n = 0;
  for (final t in thresholds) {
    if (v >= t) n++;
  }
  return n;
}

String _f(double v, [int d = 1]) => v.toStringAsFixed(d);

/// Soglia della circonferenza vita oltre la quale il rischio e' aumentato:
/// 94 cm per gli uomini, 80 per le donne (WHO 1995-2008, IDF 2005; per l'IDF
/// valgono come criteri adulti dai 16 anni). Il valore uguale alla soglia e' gia' sopra.
double waistCutoff(Sex sex) => sex == Sex.male ? 94.0 : 80.0;

bool waistRaised(Measurements m) => m.waist >= waistCutoff(m.sex);

/// BMI di Trefethen come negli script: 1,3 * peso / altezza(m)^2,5.
double bmiTrefethen(double weightKg, double heightCm) =>
    1.3 * weightKg / _pw(heightCm / 100, 2.5);

double bmiClassic(double weightKg, double heightCm) =>
    weightKg / _pw(heightCm / 100, 2);

/// BSA come BSAfun.m: media troncata di 13 formule, arrotondata a 1 decimale.
double bsaTruncatedMean(double wt, double ht, int sex) {
  double f(double a, double b, double c) => a * _pw(wt, b) * _pw(ht, c);
  final x = <double>[
    f(1 / 60, 0.5, 0.5), // Mosteller
    f(0.007184, 0.425, 0.725), // Du Bois
    f(0.024265, 0.5378, 0.3964), // Haycock
    f(0.0235, 0.51456, 0.42246), // Gehan & George
    f(0.00883, 0.444, 0.663), // Fujimoto
    f(0.007241, 0.425, 0.725), // Takahira
    f(0.00949, 0.441, 0.655), // Shuter & Aslani
    f(0.00878108, 0.434972, 0.67844), // Lipscombe
    f(0.000579479 + 0.000396003 * sex, 0.38 + 0.08 * sex, 1.24 - 0.16 * sex), // Schlich
    f(0.0333, 0.6157 - 0.0188 * _log10(wt), 0.3), // Boyd
    f(0.00713989, 0.4040, 0.7437), // Chi-Yuang
    f(0.01281, 0.44, 0.6), // Tikuisis
    (4 * wt + 7) / (90 + wt), // Costeff
  ]..sort();
  final core = x.sublist(1, x.length - 1);
  final mean = core.reduce((a, b) => a + b) / core.length;
  return mround(mean, 1);
}

class _C {
  final String label;
  final Severity sev;
  const _C(this.label, this.sev);
}

const _ok = Severity.ok;
const _w = Severity.watch;
const _a = Severity.alert;

/// Rischio di ipertensione di Parikh et al. 2008 (Weibull, Framingham).
double _hypertensionRisk(double years, List<double> x) {
  const beta = <double>[
    22.949536,
    -0.156412,
    -0.202933,
    -0.033881,
    -0.05933,
    -0.128468,
    -0.190731,
    -0.166121,
    0.00162,
  ];
  var dot = 0.0;
  for (var i = 0; i < beta.length; i++) {
    dot += beta[i] * x[i];
  }
  return 1 - math.exp(-math.exp((math.log(years) - dot) / 0.876925));
}

Report computeReport(Measurements m, Anamnesis an, AbsiTable absi) {
  final sex = m.sex.code;
  final age = m.age;
  final w = m.weight;
  final h = m.height;
  final waist = m.waist;
  final hip = m.hip;
  final wrist = m.wrist;
  final neck = m.neck;
  final calf = m.calf;
  final sbp = m.sbp;
  final dbp = m.dbp;
  final hr = m.hr;
  final hm = h / 100;

  final out = <IndexResult>[];
  final v = <String, double>{};
  final body = <String, Severity>{};
  final notes = <String>[];

  void add(String group, String key, String label, String value,
      {String unit = '',
      String reference = '',
      String comment = '',
      Severity sev = Severity.info,
      List<double> grades = const []}) {
    out.add(IndexResult(
      group: group,
      key: key,
      label: label,
      value: value,
      unit: unit,
      reference: reference,
      comment: comment,
      severity: sev,
      grades: grades,
    ));
  }

  // ---------------------------------------------------------------- Antropometria
  const gA = 'Antropometria';
  final bmi = bmiTrefethen(w, h);
  v['BMI'] = bmi;
  const bmiLabels = <_C>[
    _C('Magrezza grave', _a),
    _C('Visibilmente sottopeso', _a),
    _C('Leggermente sottopeso', _w),
    _C('Normopeso', _ok),
    _C('Sovrappeso', _w),
    _C('Obesita\' di I classe (moderata)', _a),
    _C('Obesita\' di II classe (severa)', _a),
    _C('Obesita\' di III classe (gravissima)', _a),
    _C('Obesita\' di IV classe (morbosa)', _a),
    _C('Super obeso', _a),
    _C('Iper obeso', _a),
  ];
  final bmiC = bmiLabels[cls(bmi, [15, 16, 18.5, 25, 30, 35, 40, 45, 50, 60])];
  add(gA, 'BMI', 'Indice di massa corporea (BMI di Trefethen)', _f(bmi, 2),
      unit: 'kg/m^2,5', reference: '18.5 - 25', comment: bmiC.label, sev: bmiC.sev);
  final bmic = bmiClassic(w, h);
  v['BMI_CLASSIC'] = bmic;
  add(gA, 'BMI_CLASSIC', 'BMI classico (peso/altezza^2)', _f(bmic, 2),
      unit: 'kg/m2', reference: '18.5 - 25', comment: 'Solo confronto: gli indici usano il BMI di Trefethen');
  final pi3 = w / _pw(hm, 3);
  v['PI'] = pi3;
  add(gA, 'PI', 'Indice ponderale', _f(pi3, 1), unit: 'kg/m3');
  final wLo = 18.5 * _pw(hm, 2.5) / 1.3;
  final wHi = 25 * _pw(hm, 2.5) / 1.3;
  v['W_LO'] = wLo;
  v['W_HI'] = wHi;
  add(gA, 'W_RANGE', 'Peso per BMI 18.5 - 25', '${_f(wLo)} - ${_f(wHi)}', unit: 'kg');

  final bsa = bsaTruncatedMean(w, h, sex);
  v['BSA'] = bsa;
  add(gA, 'BSA', 'Superficie corporea (media troncata di 13 formule)', _f(bsa, 1), unit: 'm2');
  final bvol = w * 1000 / 1010;
  v['BVOL'] = bvol;
  add(gA, 'BVOL', 'Volume corporeo stimato (densita\' 1,010 kg/L)', _f(bvol, 2), unit: 'L');

  // Grant e pesi ideali
  var iwl = mround(h - 100 - (h - 150) / (4 - sex * 2), 1);
  var iwc = mround(h - 100 + age / 10, 1);
  final gi = mround(h / wrist, 1);
  v['GRANT'] = gi;
  final gLo = sex == 0 ? 9.6 : 10.1;
  final gHi = sex == 0 ? 10.4 : 11.0;
  String morpho;
  if (gi > gHi) {
    iwl = mround(iwl * 0.9, 1);
    iwc = mround(iwc * 0.81, 1);
    morpho = 'Morfotipo Esile';
  } else if (gi < gLo) {
    iwl = mround(iwl * 1.1, 1);
    iwc = mround(iwc * 0.99, 1);
    morpho = 'Morfotipo Robusto';
  } else {
    iwc = mround(iwc * 0.90, 1);
    morpho = 'Morfotipo Normolineo';
  }
  v['LORENZ'] = iwl;
  v['CREFF'] = iwc;
  add(gA, 'GRANT', 'Rapporto altezza/polso (indice di Grant)', _f(gi, 1),
      comment: morpho);
  add(gA, 'LORENZ', 'Peso ideale (Lorenz)', _f(iwl), unit: 'kg');
  add(gA, 'CREFF', 'Peso ideale (Creff)', _f(iwc), unit: 'kg');

  // Polpaccio corretto per BMI (sarcopenia)
  // Le classi di BMI della correzione sono quelle OMS, definite sul BMI classico.
  final bmiR = mround(bmic, 1);
  final xb = bmiR <= 24.9 ? 0 : (bmiR <= 29.9 ? 1 : (bmiR <= 39.9 ? 2 : 3));
  final calfCorr = mround(calf - 0.5 * xb * (xb + 5), 1);
  final calfCut = 34.0 - sex;
  v['CALFCORR'] = calfCorr;
  _C calfC;
  if (calfCorr > calfCut) {
    calfC = const _C('Sarcotrofia', _ok);
  } else if (calfCorr <= calfCut - 2) {
    calfC = const _C('Sarcopenia severa', _a);
  } else {
    calfC = const _C('Sarcopenia moderata', _w);
  }
  body['calf'] = calfC.sev;
  add(gA, 'CALFCORR', 'Circonferenza del polpaccio corretta per BMI', _f(calfCorr),
      unit: 'cm', reference: '> ${_f(calfCut)}', comment: calfC.label, sev: calfC.sev);

  // Collo: conta solo come criterio STOP-BANG per le apnee notturne (uomo, BMI
  // classico > 35, collo > 40 cm). Rosso solo se i tre criteri sono presenti.
  {
    final stopBang = sex == 0 && bmic > 35 && neck > 40;
    final String comment;
    if (stopBang) {
      comment = 'Collo oltre 40 cm con BMI oltre 35 in un uomo: criterio STOP-BANG, '
          'rischio di apnee notturne da valutare';
    } else if (neck > 40) {
      comment = 'Collo oltre 40 cm, ma il criterio STOP-BANG richiede anche sesso maschile e BMI oltre 35';
    } else {
      comment = 'Sotto la soglia di screening STOP-BANG';
    }
    final sev = stopBang ? Severity.alert : _ok;
    v['NECK'] = neck;
    v['NECK_STOPBANG'] = stopBang ? 1.0 : 0.0;
    body['neck'] = sev;
    add(gA, 'NECK', 'Circonferenza del collo', _f(neck), unit: 'cm',
        reference: sex == 0 ? '< 40' : '', comment: comment, sev: sev);
  }

  // ---------------------------------------------------------------- Rischio addominale
  const gR = 'Distribuzione del grasso';
  var worstWaist = Severity.info;

  // WHR
  final whr = mround(waist / hip, 2);
  v['WHR'] = whr;
  {
    final ageIdx = age >= 69 ? 4 : cls(age.toDouble(), [30, 40, 50, 60]);
    const maleT = <List<double>>[
      [0.83, 0.89, 0.95],
      [0.84, 0.92, 0.97],
      [0.88, 0.96, 1.01],
      [0.90, 0.97, 1.03],
      [0.91, 0.99, 1.04],
    ];
    const femT = <List<double>>[
      [0.71, 0.78, 0.83],
      [0.72, 0.79, 0.85],
      [0.73, 0.80, 0.88],
      [0.74, 0.82, 0.89],
      [0.76, 0.84, 0.91],
    ];
    final t = sex == 0 ? maleT[ageIdx] : femT[ageIdx];
    const labels = <_C>[
      _C('Rischio CVD basso', _ok),
      _C('Rischio CVD moderato', _w),
      _C('Rischio CVD alto', _a),
      _C('Rischio CVD molto alto', _a),
    ];
    final c = labels[cls(whr, t)];
    body['hip'] = c.sev;
    add(gR, 'WHR', 'Rapporto vita/fianchi', _f(whr, 2),
        reference: '0 - ${_f(t[0] - 0.01, 2)}', comment: c.label, sev: c.sev);
  }

  // AVI (formula corretta)
  {
    final avi = (2 * waist * waist + 0.7 * (waist - hip) * (waist - hip)) / 1000;
    v['AVI'] = avi;
    final high = avi >= 24.5;
    add(gR, 'AVI', 'Abdominal Volume Index (AVI)', _f(avi, 2), reference: '< 24.5',
        comment: high ? 'Rischio per diabete aumentato' : 'Rischio per diabete non aumentato',
        sev: high ? _a : _ok);
  }

  // WHtR
  final whtr = mround(waist / h, 2);
  v['WHTR'] = whtr;
  {
    final t = sex == 0
        ? <double>[0.34, 0.43, 0.53, 0.58, 0.63]
        : <double>[0.34, 0.42, 0.49, 0.54, 0.58];
    const labels = <_C>[
      _C('Corporatura gracile', _w),
      _C('Corporatura esile', _ok),
      _C('Corporatura normale', _ok),
      _C('Corporatura in sovrappeso', _w),
      _C('Corporatura tarchiata', _a),
      _C('Corporatura obesa', _a),
    ];
    final c = labels[cls(whtr, t)];
    v['WHTR_CLS'] = cls(whtr, t).toDouble(); // 0 gracile ... 5 obesa
    worstWaist = worst(worstWaist, c.sev);
    add(gR, 'WHTR', 'Rapporto vita/altezza', _f(whtr, 2),
        reference: '${_f(t[1], 2)} - ${_f(t[2] - 0.01, 2)}', comment: c.label, sev: c.sev);
  }

  // ABSI + z
  {
    // Formula e tabelle NHANES di Krakauer sono costruite sul BMI classico.
    final x = waist / (10 * _pw(bmic, 2.0 / 3.0) * math.sqrt(h));
    final ref = absi.lookup(age, m.sex);
    final z = math.max(-3.0, math.min(3.0, (x - ref.mean) / ref.sd));
    v['ABSI'] = x;
    v['ABSI_Z'] = z;
    const labels = <_C>[
      _C('Rischio di mortalita\' molto basso', _ok),
      _C('Rischio di mortalita\' basso', _ok),
      _C('Rischio di mortalita\' nella media', _ok),
      _C('Rischio di mortalita\' alto', _a),
      _C('Rischio di mortalita\' molto alto', _a),
    ];
    final c = labels[cls(z, [-0.868, -0.272, 0.229, 0.798])];
    // Piu' basso e' meglio: verde sotto 0,229 (primi tre quintili di Krakauer),
    // rosso da 0,229 (rischio alto e molto alto). Nessuna zona "sotto la norma".
    add(gR, 'ABSI_Z', 'A Body Shape Index (z-score)', _f(z, 2),
        comment: c.label, sev: c.sev, grades: const [0.229]);
  }

  // CI conicita'
  {
    final ci = waist / (109 * math.sqrt(w / h));
    final cut = 1.25 - sex * 0.07;
    v['CI'] = ci;
    final hi = ci > cut;
    worstWaist = worst(worstWaist, hi ? _a : _ok);
    add(gR, 'CI', 'Indice di conicita\'', _f(ci, 2), reference: '< ${_f(cut, 2)}',
        comment: hi ? 'Rischio CVD aumentato' : 'Rischio CVD non aumentato', sev: hi ? _a : _ok);
  }

  // BRI
  {
    final bri = 364.2 - 365.5 * math.sqrt(1 - _pw(waist / h / math.pi, 2));
    final cut = sex == 0 ? 4.71 : 6.20;
    v['BRI'] = bri;
    final hi = bri > cut;
    worstWaist = worst(worstWaist, hi ? _a : _ok);
    add(gR, 'BRI', 'Body Roundness Index', _f(bri, 2), reference: '< ${_f(cut, 2)}',
        comment: hi ? 'Rischio CVD aumentato' : 'Rischio CVD non aumentato', sev: hi ? _a : _ok);
  }
  body['waist'] = worstWaist;

  // BAI
  {
    final bai = ((1000 * hip / _pw(h, 1.5)) - 18).truncateToDouble();
    v['BAI'] = bai;
    final g = age < 40 ? 0 : (age < 60 ? 1 : 2);
    const mT = <List<double>>[
      [8, 22, 27],
      [11, 24, 29],
      [13, 26, 32],
    ];
    const fT = <List<double>>[
      [21, 34, 40],
      [23, 36, 41],
      [25, 39, 44],
    ];
    final t = sex == 0 ? mT[g] : fT[g];
    const labels = <_C>[
      _C('Sottopeso', _w),
      _C('Normopeso', _ok),
      _C('Sovrappeso', _w),
      _C('Obeso', _a),
    ];
    final c = labels[cls(bai, t)];
    v['BAI_CLS'] = cls(bai, t).toDouble(); // 0 sottopeso ... 3 obeso
    add(gR, 'BAI', 'Body Adiposity Index (BAI)', _f(bai, 0), unit: '%',
        reference: '${_f(t[0], 0)} - ${_f(t[1] - 1, 0)}', comment: c.label, sev: c.sev);
  }

  // ---------------------------------------------------------------- Composizione corporea
  const gB = 'Composizione corporea';
  const bfLabels = <_C>[
    _C('Magrezza patologica', _a),
    _C('Grasso essenziale', _w),
    _C('Atleta', _ok),
    _C('Fitness', _ok),
    _C('Nella media', _ok),
    _C('Adipe patologica', _a),
  ];
  final bfT = sex == 0
      ? <double>[2, 6, 14, 18, 25]
      : <double>[10, 14, 21, 25, 32];
  final bfRef = sex == 0 ? '18 - 24' : '25 - 31';

  final bfCun = -44.988 +
      0.503 * age +
      10.689 * sex +
      3.172 * bmic -
      0.026 * bmic * bmic +
      0.181 * bmic * sex -
      0.02 * bmic * age -
      0.005 * bmic * bmic * sex +
      0.00021 * bmic * bmic * age;
  v['BF_CUN'] = bfCun;
  {
    final c = bfLabels[cls(mround(bfCun), bfT)];
    v['BF_CUN_CLS'] = cls(mround(bfCun), bfT).toDouble(); // 0 magrezza ... 5 adipe
    add(gB, 'BF_CUN', 'Grasso corporeo (CUN-BAE)', _f(mround(bfCun), 0), unit: '%',
        reference: bfRef, comment: c.label, sev: c.sev);
  }

  final rfm = 64 - 20 * h / waist + 12 * sex;
  v['RFM'] = rfm;
  {
    final c = bfLabels[cls(mround(rfm), bfT)];
    v['RFM_CLS'] = cls(mround(rfm), bfT).toDouble();
    final obCut = sex == 0 ? 30.0 : 40.0;
    final ob = rfm >= obCut;
    add(gB, 'RFM', 'Relative Fat Mass (RFM)', _f(rfm, 1), unit: '%',
        reference: '< ${_f(obCut, 0)}',
        comment: ob ? 'Oltre la soglia di obesita\' RFM' : c.label,
        sev: ob ? _a : c.sev);
  }

  final navy = sex == 0
      ? 495 / (1.0324 - 0.19077 * _log10(waist - neck) + 0.15456 * _log10(h)) - 450
      : 495 /
              (1.29579 -
                  0.35004 * _log10(waist + hip - neck) +
                  0.22100 * _log10(h)) -
          450;
  v['NAVY'] = navy;
  {
    final c = bfLabels[cls(mround(navy), bfT)];
    v['NAVY_CLS'] = cls(mround(navy), bfT).toDouble();
    add(gB, 'NAVY', 'Grasso corporeo (metodo US Navy)', _f(navy, 1), unit: '%',
        reference: bfRef, comment: c.label, sev: c.sev);
  }

  final fm = w * bfCun / 100;
  final ffm = w - fm;
  v['FM'] = fm;
  v['FFM'] = ffm;
  v['FMI'] = fm / (hm * hm);
  v['FFMI'] = ffm / (hm * hm);
  add(gB, 'FM', 'Massa grassa (da CUN-BAE)', _f(fm), unit: 'kg');
  add(gB, 'FFM', 'Massa magra (da CUN-BAE)', _f(ffm), unit: 'kg');
  add(gB, 'FMI', 'Fat Mass Index', _f(fm / (hm * hm)), unit: 'kg/m2');
  // Riferimento FFMI: Schutz, Kyle, Pichard, Int J Obes 2002 (5-95 percentile, BIA).
  // Uomini: nessuna variazione significativa con l'eta'. Donne: dato per 18-34 anni.
  final ffmiRef = sex == 0
      ? '16.8 - 21.1'
      : (age <= 34 ? '13.8 - 17.6' : '');
  add(gB, 'FFMI', 'Fat-Free Mass Index', _f(ffm / (hm * hm)), unit: 'kg/m2',
      reference: ffmiRef,
      comment: ffmiRef.isEmpty ? '' : 'Riferimento Schutz 2002 (bioimpedenza); valore da CUN-BAE');

  final boer = sex == 0 ? 0.407 * w + 0.267 * h - 19.2 : 0.252 * w + 0.473 * h - 48.3;
  final hume = sex == 0
      ? 0.32810 * w + 0.33929 * h - 29.5336
      : 0.29569 * w + 0.41813 * h - 43.2933;
  final james = sex == 0
      ? 1.1 * w - 128 * _pw(w / h, 2)
      : 1.07 * w - 148 * _pw(w / h, 2);
  v['LBM_BOER'] = boer;
  v['LBM_HUME'] = hume;
  v['LBM_JAMES'] = james;
  final lbmMean = (boer + hume + james) / 3;
  v['LBM'] = lbmMean;
  add(gB, 'LBM', 'Massa magra da altezza e peso (media di Boer, Hume, James)', _f(lbmMean), unit: 'kg');

  // ---------------------------------------------------------------- Energia
  const gE = 'Metabolismo';
  final bmr = mround(10 * w + 6.25 * h - 5 * age + 5 - 166 * sex);
  v['BMR'] = bmr;
  final bee = mround(sex == 0
      ? 66 + 13.7 * w + 5 * h - 6.8 * age
      : 655 + 9.6 * w + 1.8 * h - 4.7 * age);
  v['BEE'] = bee;
  final katch = 370 + 21.6 * ffm;
  v['KATCH'] = katch;
  final bmrMean = (bmr + bee + katch) / 3;
  v['BMR_MEAN'] = bmrMean;
  add(gE, 'BMR_MEAN', 'Metabolismo basale (media di Mifflin-St Jeor, Harris-Benedict, Katch-McArdle)',
      _f(bmrMean, 0), unit: 'kcal/die');

  // ---------------------------------------------------------------- Cuore e pressione
  const gCuore = 'Cuore';
  const gArt = 'Pressione e arterie';
  const gPer = 'Periferia e perfusione';
  final pp = sbp - dbp;
  final map = dbp + 0.01 * math.exp(4.14 - 40.74 / hr) * pp;
  v['PP'] = pp;
  v['MAP'] = map;

  // Classi pressorie
  final sbpC = cls(sbp, [80, 90, 100, 110, 130, 140, 160, 180]);
  final dbpC = cls(dbp, [60, 65, 70, 75, 85, 90, 100, 110]);
  final bpc = math.max(sbpC, dbpC) + 1; // 1..9
  const bpLabels = <_C>[
    _C('Ipotensione grave', _a),
    _C('Ipotensione moderata', _a),
    _C('Ipotensione lieve', _w),
    _C('Normale bassa', _ok),
    _C('Normale', _ok),
    _C('Normale alta', _w),
    _C('Ipertensione lieve', _a),
    _C('Ipertensione moderata', _a),
    _C('Ipertensione grave', _a),
  ];
  final bpCl = bpLabels[bpc - 1];
  v['BPC'] = bpc.toDouble();
  // Tre stati: iperteso da 140/90, ipoteso sotto 90/60 (come la classe "Ipertensione lieve").
  // Basta un solo valore oltre soglia: l'ipertensione ha la precedenza
  // (es. 150/55, sistolica isolata con diastolica bassa, e' iperteso).
  final bpZone = (sbp >= 140 || dbp >= 90) ? 1 : ((sbp < 90 || dbp < 60) ? -1 : 0);
  v['BPZONE'] = bpZone.toDouble();
  add(gArt, 'BP', 'Pressione arteriosa', '${_f(sbp, 0)}/${_f(dbp, 0)}', unit: 'mmHg',
      comment: bpZone < 0 ? 'Ipoteso' : (bpZone > 0 ? 'Iperteso' : 'Normoteso'), sev: bpCl.sev);

  // Frequenza cardiaca per fascia d'eta'
  final ag = cls(age.toDouble(), [26, 36, 46, 56, 66]); // 0..5
  const euLo = [70, 71, 71, 72, 72, 70];
  const euHi = [73, 74, 75, 76, 75, 73];
  const tcHi = [81, 81, 82, 83, 81, 79];
  const brMildLo = [66, 66, 67, 68, 68, 66];
  const brGoodLo = [62, 62, 63, 64, 62, 62];
  const brExcLo = [56, 55, 57, 58, 57, 56];
  const brAthLo = [49, 49, 50, 50, 51, 50];
  _C hrC;
  if (hr > euHi[ag]) {
    hrC = hr > tcHi[ag] ? const _C('Tachicardia severa', _a) : const _C('Tachicardia lieve', _w);
  } else if (hr >= euLo[ag]) {
    hrC = const _C('Eucardia', _ok);
  } else if (hr >= brMildLo[ag]) {
    hrC = const _C('Bradicardia lieve', _ok);
  } else if (hr >= brGoodLo[ag]) {
    hrC = const _C('Bradicardia - Frequenza buona', _ok);
  } else if (hr >= brExcLo[ag]) {
    hrC = const _C('Bradicardia - Frequenza eccellente', _ok);
  } else if (hr >= brAthLo[ag]) {
    hrC = const _C('Bradicardia - Frequenza da atleta', _ok);
  } else {
    hrC = const _C('Bradicardia eccessiva', _a);
  }
  final hrZone = hr < euLo[ag] ? -1 : (hr > euHi[ag] ? 1 : 0);
  v['HRZONE'] = hrZone.toDouble();
  add(gCuore, 'HR', 'Frequenza cardiaca a riposo', _f(hr, 0), unit: 'bpm',
      reference: '${euLo[ag]} - ${euHi[ag]}',
      comment: hrZone < 0 ? 'Bradicardico' : (hrZone > 0 ? 'Tachicardico' : 'Eucardico'), sev: hrC.sev);

  // Frequenza massima
  final fcm = sex == 0
      ? 203.7 / (1 + math.exp(0.033 * (age - 104.3)))
      : 190.2 / (1 + math.exp(0.0453 * (age - 107.5)));
  v['FCM'] = fcm;
  add(gCuore, 'FCM', 'Frequenza cardiaca massima stimata', _f(fcm, 0), unit: 'bpm');

  // Pressione di pulsazione
  {
    const labels = <_C>[
      _C('Ipovolemia severa', _a),
      _C('Gittata ridotta', _w),
      _C('Elasticita\' vascolare normale', _ok),
      _C('Rigidita\' arteriosa lieve', _w),
      _C('Rigidita\' arteriosa marcata', _a),
    ];
    final c = labels[cls(pp, [25, 30, 56, 66])];
    add(gArt, 'PP', 'Pressione di pulsazione', _f(pp, 0), unit: 'mmHg',
        reference: '30 - 55', comment: c.label, sev: c.sev);
  }
  // MAP
  {
    const labels = <_C>[
      _C('Ipoperfusione probabile', _a),
      _C('Ipotensione lieve', _w),
      _C('Perfusione adeguata', _ok),
      _C('Lieve ipertono vasale', _w),
      _C('Ipertensione significativa', _a),
    ];
    final c = labels[cls(map, [60, 70, 106, 116])];
    add(gArt, 'MAP', 'Pressione arteriosa media (MAP)', _f(map, 0), unit: 'mmHg',
        reference: '70 - 105', comment: c.label, sev: c.sev);
  }
  // Indice di rigidita'
  final ai = mround(pp / map, 2);
  v['AI'] = ai;
  {
    const labels = <_C>[
      _C('Vasodilatazione', _w),
      _C('Compliance normale', _ok),
      _C('Rigidita\' arteriosa lieve', _w),
      _C('Rigidita\' arteriosa moderata', _a),
      _C('Rigidita\' arteriosa marcata', _a),
    ];
    final c = labels[cls(ai, [0.30, 0.56, 0.66, 0.76])];
    add(gArt, 'AI', 'Indice di rigidita\' arteriosa', _f(ai, 2), reference: '0.30 - 0.55',
        comment: c.label, sev: c.sev);
  }
  // Riserva cronotropa
  final hrr = fcm - hr;
  v['HRR'] = hrr;
  {
    const labels = <_C>[
      _C('Riserva cronotropa ridotta', _a),
      _C('Bradicardia/Tono vagale', _w),
      _C('Riserva cronotropa normale', _ok),
      _C('Riserva cronotropa buona', _ok),
      _C('Riserva cronotropa ottima', _ok),
    ];
    final c = labels[cls(hrr, [60, 80, 121, 151])];
    add(gCuore, 'HRR', 'Frequenza cardiaca di riserva', _f(hrr, 0), unit: 'bpm',
        reference: '80 - 120', comment: c.label, sev: c.sev);
  }
  // MSI
  final msi = mround(hr / map, 2);
  v['MSI'] = msi;
  Severity msiSev;
  {
    const labels = <_C>[
      _C('Profilo vagale', _ok),
      _C('Profilo normale', _ok),
      _C('Stress emodinamico', _w),
      _C('Instabilita\' emodinamica', _a),
      _C('Shock emodinamico', _a),
    ];
    final c = labels[cls(msi, [0.70, 1.00, 1.30, 1.60])];
    msiSev = c.sev;
    add(gPer, 'MSI', 'Modified Shock Index', _f(msi, 2), unit: 'bpm/mmHg',
        reference: '0.70 - 0.99', comment: c.label, sev: c.sev);
  }
  // RPP
  final rpp = sbp * hr;
  v['RPP'] = rpp;
  {
    const labels = <_C>[
      _C('Bradicardia/ipocinesia', _w),
      _C('Tono vagale', _ok),
      _C('Consumo miocardico fisiologico', _ok),
      _C('Stress/ansia/febbre', _w),
      _C('Carico miocardico elevato', _a),
      _C('Carico miocardico eccessivo', _a),
      _C('Rischio ischemia', _a),
    ];
    final c = labels[cls(rpp, [7000, 10000, 15000, 20000, 25000, 30000])];
    add(gCuore, 'RPP', 'Prodotto frequenza-pressione (RPP)', _f(rpp, 0), unit: 'bpm*mmHg',
        reference: '10000 - 14999', comment: c.label, sev: c.sev);
  }
  // Stroke volume (Starr, ricalibrato su 70 mL)
  final svRaw = 90.97 + 0.54 * pp - 0.57 * dbp - 0.61 * age;
  final svRef = 90.97 + 0.54 * 42 - 0.57 * 78 - 0.61 * age;
  final svPct = mround(svRaw / svRef * 100);
  final sv = mround(svRaw * 70 / svRef);
  v['SV'] = sv;
  v['SVPCT'] = svPct;
  {
    const labels = <_C>[
      _C('Ipovolemia severa', _a),
      _C('Gittata ridotta', _w),
      _C('Gittata adeguata', _ok),
      _C('Stato ipercinetico', _w),
      _C('Iperdinamia marcata', _a),
    ];
    final c = labels[cls(svPct, [70, 90, 111, 131])];
    add(gCuore, 'SV', 'Stroke Volume', _f(sv, 0), unit: 'mL', reference: '60 - 100',
        comment: '${c.label} (${_f(svPct, 0)}% dell\'atteso)', sev: c.sev);
  }
  // Gittata cardiaca
  final co = mround(sv * hr / 1000, 1);
  v['CO'] = co;
  {
    const labels = <_C>[
      _C('Ipoperfusione', _a),
      _C('Bradicardia/Adattamento', _w),
      _C('Perfusione adeguata', _ok),
      _C('Stato ipercinetico', _w),
      _C('Iperdinamia marcata', _a),
    ];
    final c = labels[cls(co, [3.0, 3.5, 7.0, 8.1])];
    add(gCuore, 'CO', 'Gittata cardiaca', _f(co, 1), unit: 'L/min', reference: '3.5 - 6.9',
        comment: c.label, sev: c.sev);
  }
  // Cardiac index
  final cidx = mround(co / bsa, 1);
  v['CIDX'] = cidx;
  {
    const labels = <_C>[
      _C('Ipoperfusione', _a),
      _C('Bradicardia/Adattamento', _w),
      _C('Perfusione adeguata', _ok),
      _C('Stato ipercinetico', _w),
      _C('Iperdinamia marcata', _a),
    ];
    final c = labels[cls(cidx, [2.0, 2.5, 4.0, 4.5])];
    add(gCuore, 'CIDX', 'Cardiac Index', _f(cidx, 1), unit: 'L/min/m2', reference: '2.5 - 3.9',
        comment: c.label, sev: c.sev);
  }
  // LCWI
  final lcwi = mround(2.2222 * cidx * map);
  v['LCWI'] = lcwi;
  {
    const labels = <_C>[
      _C('Depressione pompa ventricolare', _a),
      _C('Profilo vagale', _w),
      _C('Adeguato lavoro ventricolare', _ok),
      _C('Carico ventricolare aumentato', _w),
      _C('Sovraccarico ventricolare', _a),
    ];
    final c = labels[cls(lcwi, [300, 400, 900, 1050])];
    add(gCuore, 'LCWI', 'Left Cardiac Work Index', _f(lcwi, 0), unit: 'mW/m2',
        reference: '400 - 900', comment: c.label, sev: c.sev);
  }
  // SVRI
  final svri = mround(bsa * 80 * (map - 5) / co / 1000, 1);
  v['SVRI'] = svri;
  {
    const labels = <_C>[
      _C('Vasodilatazione', _w),
      _C('Resistenza ottimale', _ok),
      _C('Tono vasale aumentato/compenso', _w),
      _C('Vasocostrizione', _a),
      _C('Vasocostrizione marcata', _a),
    ];
    final c = labels[cls(svri, [1.8, 2.9, 3.5, 4.0])];
    add(gPer, 'SVRI', 'Indice di resistenza vascolare sistemica', _f(svri, 1), unit: 'kU*m2',
        reference: '1.8 - 2.8', comment: c.label, sev: c.sev);
  }
  // ePWV (Greve 2016, equazione per popolazione generale)
  final mbp = dbp + 0.4 * (sbp - dbp);
  final epwv = 9.58748315543126 -
      0.402467539733184 * age +
      4.56020798207263e-3 * age * age -
      2.6207705511664e-5 * age * age * mbp +
      3.1762450559276e-3 * age * mbp -
      1.83215068503821e-2 * mbp;
  v['EPWV'] = epwv;
  {
    final hi = epwv >= 10;
    add(gArt, 'EPWV', 'Velocita\' dell\'onda di polso stimata (ePWV)', _f(epwv, 1), unit: 'm/s',
        reference: '< 10',
        comment: hi
            ? 'Sopra la soglia di 10 m/s: stima da età e pressione, da confermare con misura'
            : 'Sotto la soglia di 10 m/s (stima da età e pressione)',
        sev: hi ? _a : _ok);
  }

  // Distretto "cuore": gravita' massima tra pressione, frequenza e MSI
  body['heart'] = worst(worst(bpCl.sev, hrC.sev), msiSev);

  // ---------------------------------------------------------------- Zone di allenamento
  String r0(double x) => x.toStringAsFixed(0);
  final zonesFc = <HrZone>[
    HrZone('Zona 0 - Riposo', '< ${r0(fcm * 0.5)} bpm'),
    HrZone('Zona 1 - Riscaldamento', '${r0(fcm * 0.5)} - ${r0(fcm * 0.6 - 1)} bpm'),
    HrZone('Zona 2 - Controllo del peso', '${r0(fcm * 0.6)} - ${r0(fcm * 0.7 - 1)} bpm'),
    HrZone('Zona 3 - Aerobiosi', '${r0(fcm * 0.7)} - ${r0(fcm * 0.8 - 1)} bpm'),
    HrZone('Zona 4 - Anaerobiosi', '${r0(fcm * 0.8)} - ${r0(fcm * 0.9 - 1)} bpm'),
    HrZone('Zona 5 - Massima intensita\'', '${r0(fcm * 0.9)} - ${r0(fcm)} bpm'),
  ];
  String kz(double p0, double p1) =>
      '${r0(hr + p0 * (fcm - hr))} - ${r0(hr + p1 * (fcm - hr))} bpm';
  final zonesKa = <HrZone>[
    HrZone('50 - 60% della riserva', kz(0.5, 0.6)),
    HrZone('60 - 70% della riserva', kz(0.6, 0.7)),
    HrZone('70 - 80% della riserva', kz(0.7, 0.8)),
    HrZone('80 - 90% della riserva', kz(0.8, 0.9)),
    HrZone('90 - 100% della riserva', kz(0.9, 1.0)),
  ];

  // ---------------------------------------------------------------- Rischio ipertensione
  const gH = 'Rischio di ipertensione (Framingham)';
  if (an.answered && !an.onAntihypertensives) {
    final smoke = an.smoker ? 1.0 : 0.0;
    final php = an.parentsHypertensive.toDouble();
    final x = <double>[1, age.toDouble(), sex.toDouble(), bmic, sbp, dbp, smoke, php, age * dbp];
    final ref = <double>[1, age.toDouble(), sex.toDouble(), 22.5, 110, 70, 0, 0, age * 70.0];
    for (final y in const [1.0, 2.0, 4.0]) {
      final r = _hypertensionRisk(y, x) * 100;
      final r0v = _hypertensionRisk(y, ref) * 100;
      v['HT${y.toInt()}'] = r;
      v['HTREF${y.toInt()}'] = r0v;
      // Nessuna soglia sul rapporto: o si e' sopra il profilo ottimale o no.
      final mult = r / r0v;
      v['HTX${y.toInt()}'] = mult;
      final sev = r > r0v ? _a : _ok;
      add(gH, 'HT${y.toInt()}', 'Rischio a ${y.toInt()} ${y == 1.0 ? 'anno' : 'anni'}',
          _f(r, 2), unit: '%', sev: sev);
    }
  } else if (an.answered && an.onAntihypertensives) {
    notes.add('Rischio di ipertensione non calcolato: il modello e\' per soggetti non in terapia antipertensiva.');
  } else {
    notes.add('Rischio di ipertensione non calcolato: servono le domande anamnestiche facoltative.');
  }

  if (age < 18) {
    notes.add('Le soglie degli indici sono per adulti: sotto i 18 anni i risultati non sono interpretabili.');
  }

  return Report(
    age: age,
    results: _ordered(out),
    values: v,
    body: body,
    zonesFcmax: zonesFc,
    zonesKarvonen: zonesKa,
    notes: notes,
  );
}

/// Ordine di visualizzazione dentro ogni gruppo: prima gli indici di uso
/// corrente, poi quelli derivati. Le chiavi non elencate restano in coda,
/// nell'ordine di calcolo.
const _order = <String>[
  // Antropometria
  'BMI', 'BMI_CLASSIC', 'PI', 'W_RANGE', 'GRANT', 'LORENZ', 'CREFF', 'NECK', 'CALFCORR', 'BSA', 'BVOL',
  // Distribuzione del grasso
  'WHTR', 'WHR', 'ABSI_Z', 'BRI', 'CI', 'AVI', 'BAI',
  // Composizione corporea
  'BF_CUN', 'RFM', 'NAVY', 'FM', 'FFM', 'FMI', 'FFMI', 'LBM',
  // Metabolismo
  'BMR_MEAN',
  // Cuore: frequenza, riserva, gittata, lavoro. Pressione e arterie. Periferia.
  'HR', 'HRR', 'FCM', 'SV', 'CO', 'CIDX', 'LCWI', 'RPP',
  'BP', 'PP', 'MAP', 'AI', 'EPWV',
  'SVRI', 'MSI',
];

List<IndexResult> _ordered(List<IndexResult> list) {
  final pos = <String, int>{for (var i = 0; i < _order.length; i++) _order[i]: i};
  final indexed = [for (var i = 0; i < list.length; i++) MapEntry(i, list[i])];
  indexed.sort((a, b) {
    final pa = pos[a.value.key] ?? 1000 + a.key;
    final pb = pos[b.value.key] ?? 1000 + b.key;
    return pa.compareTo(pb);
  });
  return [for (final e in indexed) e.value];
}
