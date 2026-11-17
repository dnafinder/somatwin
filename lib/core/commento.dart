/// Commento automatico in linguaggio naturale.
///
/// Nessuna AI e nessuna rete: regole fisse sugli esiti degli indici gia'
/// calcolati e frasi di un catalogo. Stessi dati, stesso testo.
///
/// Il significato di un valore dipende dal contesto (un grasso basso o una
/// frequenza bassa non dicono la stessa cosa in un atleta e in un sottopeso),
/// quindi ogni misura passa prima dal [Profilo] del soggetto.
library;

import 'indices.dart';
import 'models.dart';

const String kUrlCardio = 'https://www.medylab-na.it/p/stima-del-rischio-cardio-metabolico/';
const String kUrlDoppiaLettura = 'https://dnafinder.github.io/doppia-lettura/';

enum Esito { favorevole, daOsservare, daApprofondire }

extension EsitoX on Esito {
  String get label {
    switch (this) {
      case Esito.favorevole:
        return 'Favorevole';
      case Esito.daOsservare:
        return 'Da osservare';
      case Esito.daApprofondire:
        return 'Da approfondire';
    }
  }

  Severity get severity {
    switch (this) {
      case Esito.favorevole:
        return Severity.ok;
      case Esito.daOsservare:
        return Severity.watch;
      case Esito.daApprofondire:
        return Severity.alert;
    }
  }
}

/// Contesto corporeo, valutato in questo ordine.
enum Profilo { sottopeso, adiposo, muscolare, standard }

class CommentSection {
  final String title;
  final String text;
  final Esito esito;
  const CommentSection(this.title, this.text, this.esito);
}

class CtaLink {
  final String label;
  final String url;
  const CtaLink(this.label, this.url);
}

class Comment {
  final Profilo profilo;
  final List<CommentSection> sections;
  final String summary;

  /// Presente solo se almeno un'area non e' favorevole.
  final String? lifestyle;
  final String ctaLead;
  final String ctaBody;
  final List<CtaLink> links;
  final String closing;

  const Comment({
    required this.profilo,
    required this.sections,
    required this.summary,
    required this.lifestyle,
    required this.ctaLead,
    required this.ctaBody,
    required this.links,
    required this.closing,
  });

  /// Tutto il testo, senza formattazione (test e copia).
  String get plainText {
    final out = <String>[
      for (final s in sections) '${s.title}\n${s.text}',
      summary,
      if (lifestyle != null) lifestyle!,
      '$ctaLead $ctaBody',
      closing,
    ];
    return out.join('\n\n');
  }
}

const String _chiusura = "Il commento è informativo: l'interpretazione clinica spetta al medico.";

const String _ctaBody =
    "La revisione dello stile di vita mette insieme tre letture. La stima del rischio "
    "cardio-metabolico di MEDyLAB guarda glicemia, insulina e lipidi, con esami da fare nel "
    "laboratorio che preferisci. La variabilità cardiaca (HRV), a cura di Self Coherence, misura "
    "per cinque giorni come reagisce il sistema nervoso autonomo, con un sensore da indossare. "
    "Il profilo ASI di MEDyLAB legge il ritmo del cortisolo salivare in quattro prelievi in una "
    "giornata, con un kit da fare a casa. Sono strumenti informativi e orientati al benessere: "
    "non sostituiscono la visita medica.";

const String _stileDiVita =
    "Attività fisica regolare e controlli periodici aiutano a seguire questi valori nel tempo; "
    "per indicazioni specifiche rivolgiti al tuo medico.";

// ------------------------------------------------------------------ utilita'

Severity? _sev(Report r, String k) => r.byKey(k)?.severity;

bool _off(Report r, String k) {
  final s = _sev(r, k);
  return s == Severity.watch || s == Severity.alert;
}

String _shown(Report r, String k) => r.byKey(k)?.value ?? '';

double _num(Report r, String k) => r.values[k] ?? 0;

Esito _fromSev(Severity? s) {
  if (s == Severity.alert) return Esito.daApprofondire;
  if (s == Severity.watch) return Esito.daOsservare;
  return Esito.favorevole;
}

Esito _max(Esito a, Esito b) => a.index >= b.index ? a : b;

String _elenco(List<String> xs) {
  if (xs.isEmpty) return '';
  if (xs.length == 1) return xs.first;
  return '${xs.sublist(0, xs.length - 1).join(', ')} e ${xs.last}';
}

String _morfotipo(Report r) {
  final c = r.byKey('GRANT')?.comment ?? '';
  const prefix = 'Morfotipo ';
  final s = c.startsWith(prefix) ? c.substring(prefix.length) : c;
  return s.toLowerCase();
}

// ------------------------------------------------------------------ profilo

/// Grasso alto se almeno due dei tre metodi lo dicono: CUN-BAE parte dal BMI e
/// in un soggetto muscoloso lo sovrastima, gli altri due guardano la vita.
bool _grassoAlto(Report r) =>
    const ['BF_CUN_CLS', 'RFM_CLS', 'NAVY_CLS'].where((k) => _num(r, k) >= 5).length >= 2;

/// Sottopeso: BMI sotto 18,5. Adiposo: BMI da 30 con almeno un segnale
/// addominale (vita, rapporto vita/altezza, grasso percentuale alto). Muscolare:
/// BMI da 25 con vita, rapporto vita/altezza e grasso tutti favorevoli.
Profilo profiloDi(Report r, Measurements m) {
  final bmi = _num(r, 'BMI');
  final addominale = waistRaised(m) || _num(r, 'WHTR_CLS') >= 3 || _grassoAlto(r);
  if (bmi < 18.5) return Profilo.sottopeso;
  if (bmi >= 30 && addominale) return Profilo.adiposo;
  if (bmi >= 25 && !addominale) return Profilo.muscolare;
  return Profilo.standard;
}

// ------------------------------------------------------------------ aree

CommentSection _pesoMorfotipo(Report r, Profilo p) {
  final parts = <String>[];
  var esito = Esito.favorevole;
  final bmi = _shown(r, 'BMI');
  final fascia = (r.byKey('BMI')?.comment ?? '').toLowerCase();
  final morfo = _morfotipo(r);
  final bmiSev = _sev(r, 'BMI');

  if (bmiSev == Severity.ok) {
    parts.add("Peso e statura rientrano nell'intervallo di riferimento (BMI $bmi) e il morfotipo è $morfo.");
  } else if (p == Profilo.muscolare) {
    parts.add('Il BMI è $bmi, nella fascia $fascia, ma il peso elevato non si accompagna a '
        'adiposità addominale ed è compatibile con una massa muscolare importante. '
        'Il morfotipo è $morfo.');
  } else {
    esito = _fromSev(bmiSev);
    final coda = bmiSev == Severity.alert ? ', che merita un approfondimento' : '';
    parts.add('Il BMI è $bmi, nella fascia $fascia$coda. Il morfotipo è $morfo.');
  }

  if (_num(r, 'NECK_STOPBANG') > 0) {
    parts.add('Il collo supera 40 cm con BMI oltre 35: sono due dei criteri dello STOP-BANG '
        'per le apnee notturne, da valutare con il medico.');
    esito = Esito.daApprofondire;
  }
  if (_off(r, 'CALFCORR')) {
    parts.add('Il polpaccio, corretto per il BMI, è sotto la soglia di riferimento per la massa muscolare.');
    esito = _max(esito, _fromSev(_sev(r, 'CALFCORR')));
  }
  return CommentSection('Peso e morfotipo', parts.join(' '), esito);
}

CommentSection _distribuzione(Report r, Measurements m, Profilo p) {
  final taglio = waistCutoff(m.sex).toStringAsFixed(0);
  final voci = <(String, bool)>[
    (waistRaised(m) ? 'vita (oltre $taglio cm)' : 'vita', waistRaised(m)),
    ('rapporto vita/altezza', _num(r, 'WHTR_CLS') >= 3),
    ('rapporto vita/fianchi', _off(r, 'WHR')),
    ('ABSI', _sev(r, 'ABSI_Z') == Severity.alert),
    ('BRI', _sev(r, 'BRI') == Severity.alert),
    ('indice di conicità', _sev(r, 'CI') == Severity.alert),
    ('AVI', _sev(r, 'AVI') == Severity.alert),
    ('BAI', _num(r, 'BAI_CLS') >= 2),
  ];
  final no = [for (final v in voci) if (v.$2) v.$1];
  final si = [for (final v in voci) if (!v.$2) v.$1];
  final tot = voci.length;

  if (no.isEmpty) {
    return const CommentSection(
        'Distribuzione del grasso',
        'La distribuzione del grasso non mostra segnali di accumulo addominale: vita, '
            'rapporto vita/altezza e ABSI vanno nella stessa direzione.',
        Esito.favorevole);
  }
  String testo;
  if (no.length * 4 <= tot) {
    testo = 'Prevalgono i segnali favorevoli, con ${_elenco(no)} fuori riferimento.';
  } else if (no.length * 4 >= tot * 3) {
    testo = 'La maggior parte degli indici indica un accumulo di grasso addominale: '
        '${_elenco(no)} sono fuori riferimento.';
  } else {
    testo = 'Il quadro non è univoco: ${_elenco(si)} sono nella norma, ${_elenco(no)} no.';
  }
  if (p == Profilo.muscolare) {
    testo += ' In un fisico muscoloso un tronco ampio può alzare alcuni di questi indici '
        'senza che ci sia più grasso.';
  }
  final esito = no.length * 2 >= tot ? Esito.daApprofondire : Esito.daOsservare;
  return CommentSection('Distribuzione del grasso', testo, esito);
}

CommentSection _composizione(Report r, Profilo p) {
  final classi = [_num(r, 'BF_CUN_CLS'), _num(r, 'RFM_CLS'), _num(r, 'NAVY_CLS')]..sort();
  final mediana = classi[1];
  final scarto = classi[2] - classi[0];
  var esito = Esito.favorevole;
  String testo;

  if (mediana >= 5) {
    testo = "La percentuale di grasso è sopra l'intervallo di riferimento.";
    esito = Esito.daApprofondire;
  } else if (mediana <= 2) {
    if (p == Profilo.sottopeso) {
      testo = 'Percentuale di grasso bassa in un quadro di basso peso: scarse riserve '
          'energetiche, da valutare con il medico.';
      esito = Esito.daApprofondire;
    } else {
      testo = "La percentuale di grasso è sotto l'intervallo di riferimento, compatibile con "
          'un profilo molto magro o atletico.';
    }
  } else {
    testo = "La percentuale di grasso è nell'intervallo atteso per sesso ed età.";
  }
  if (scarto >= 2) {
    testo += ' I tre metodi di stima non coincidono '
        '(${_shown(r, 'BF_CUN')}%, ${_shown(r, 'RFM')}% e ${_shown(r, 'NAVY')}%): '
        'le stime da sole misure sono approssimate e vanno lette come ordine di grandezza.';
  }
  return CommentSection('Composizione corporea', testo, esito);
}

String _descrizionePressione(int bpc) {
  switch (bpc) {
    case 1:
      return 'molto bassa (ipotensione grave)';
    case 2:
      return 'bassa (ipotensione moderata)';
    case 3:
      return 'bassa (ipotensione lieve)';
    case 4:
      return 'nella norma, nella parte bassa';
    case 5:
      return 'nella norma';
    case 6:
      return 'normale alta';
    case 7:
      return 'alta (ipertensione lieve)';
    case 8:
      return 'alta (ipertensione moderata)';
    default:
      return 'molto alta (ipertensione grave)';
  }
}

CommentSection _cuore(Report r, Profilo p) {
  final parts = <String>[];
  var esito = Esito.favorevole;

  // Pressione
  final bpc = _num(r, 'BPC').round();
  final val = '${_shown(r, 'BP')} mmHg';
  final desc = _descrizionePressione(bpc);
  final bpEsito = _fromSev(_sev(r, 'BP'));
  final ripeti = 'è una singola misura, quindi conviene ripeterla in giorni e momenti diversi';
  if (bpc >= 6) {
    if (p == Profilo.adiposo) {
      parts.add("La pressione è $desc ($val): l'eccesso di grasso è uno dei fattori che la sostengono.");
      esito = _max(esito, _max(bpEsito, Esito.daOsservare));
    } else if (p == Profilo.sottopeso) {
      parts.add('La pressione è $desc ($val): con basso peso è una combinazione meno frequente, '
          'da valutare con il medico.');
      esito = Esito.daApprofondire;
    } else {
      parts.add('La pressione è $desc ($val): $ripeti.');
      esito = _max(esito, bpEsito);
    }
  } else if (bpc <= 3) {
    if (p == Profilo.muscolare && bpc == 3) {
      parts.add('La pressione è bassa ($val), frequente nelle persone allenate.');
    } else if (p == Profilo.sottopeso) {
      parts.add('La pressione è $desc ($val): con basso peso va valutata con il medico.');
      esito = _max(esito, _max(bpEsito, Esito.daOsservare));
    } else {
      parts.add('La pressione è $desc ($val): $ripeti.');
      esito = _max(esito, bpEsito);
    }
  } else {
    parts.add('La pressione è $desc ($val).');
    esito = _max(esito, bpEsito);
  }

  // Frequenza
  final zonaFc = _num(r, 'HRZONE').round();
  final hr = '${_shown(r, 'HR')} bpm';
  final fcSev = _sev(r, 'HR');
  final fcMolto = fcSev == Severity.alert;
  if (zonaFc == 0) {
    parts.add('La frequenza a riposo è nella norma ($hr).');
  } else if (zonaFc > 0) {
    parts.add('La frequenza a riposo è alta ($hr): conviene misurarla di nuovo a riposo, '
        'dopo qualche minuto da seduti.');
    esito = _max(esito, _fromSev(fcSev));
  } else {
    switch (p) {
      case Profilo.muscolare:
        if (fcMolto) {
          parts.add('La frequenza a riposo è molto bassa ($hr): in un profilo atletico può essere '
              'normale, ma va confermata con misure ripetute e, se ci sono sintomi, valutata dal medico.');
          esito = _max(esito, Esito.daOsservare);
        } else {
          parts.add('La frequenza a riposo è bassa ($hr), compatibile con un condizionamento atletico.');
        }
      case Profilo.sottopeso:
        parts.add('La frequenza a riposo è bassa ($hr) in un quadro di basso peso: va valutata con il medico.');
        esito = _max(esito, _max(_fromSev(fcSev), Esito.daOsservare));
      case Profilo.adiposo:
        parts.add('La frequenza a riposo è bassa ($hr) in un quadro di eccesso di grasso: '
            'è una combinazione insolita e merita un approfondimento.');
        esito = Esito.daApprofondire;
      case Profilo.standard:
        if (fcMolto) {
          parts.add('La frequenza a riposo è molto bassa ($hr): va valutata con il medico.');
          esito = Esito.daApprofondire;
        } else {
          parts.add('La frequenza a riposo è bassa ($hr): in assenza di sintomi è spesso una '
              'variante normale. Conviene confermarla con misure ripetute.');
        }
    }
  }

  // Indici derivati. MSI e RPP dipendono dalla frequenza: con frequenza bassa
  // il loro scostamento e' gia' detto sopra.
  final derivati = <(String, String)>[
    ('MAP', 'pressione media'),
    ('PP', 'pressione differenziale'),
    ('AI', 'indice di rigidità arteriosa'),
    ('EPWV', "velocità dell'onda di polso stimata"),
    if (zonaFc >= 0) ('MSI', 'indice di shock modificato'),
    if (zonaFc >= 0) ('RPP', 'prodotto frequenza-pressione'),
  ];
  final fuori = [for (final d in derivati) if (_off(r, d.$1)) d];
  if (fuori.isNotEmpty) {
    parts.add('Alcuni indici derivati (${_elenco([for (final d in fuori) d.$2])}) sono fuori riferimento.');
    for (final d in fuori) {
      esito = _max(esito, _fromSev(_sev(r, d.$1)));
    }
  }

  // Rischio di ipertensione (solo con anamnesi). Qui conta al massimo come
  // "da osservare": quasi tutti superano il profilo ottimale e non c'e'
  // una soglia sul rapporto.
  if (r.values.containsKey('HT4') && r.values.containsKey('HTREF4')) {
    final x = _shown(r, 'HT4');
    final y = _num(r, 'HTREF4').toStringAsFixed(2);
    if (_num(r, 'HT4') > _num(r, 'HTREF4')) {
      parts.add('Il rischio stimato di sviluppare ipertensione a 4 anni è $x%, contro $y% del profilo ottimale.');
      esito = _max(esito, Esito.daOsservare);
    } else {
      parts.add('Il rischio stimato di ipertensione a 4 anni ($x%) non supera quello del profilo ottimale ($y%).');
    }
  }
  return CommentSection('Cuore e pressione', parts.join(' '), esito);
}

// ------------------------------------------------------------------ insieme

Comment buildComment(Report r, Measurements m) {
  final p = profiloDi(r, m);
  final sections = <CommentSection>[
    _pesoMorfotipo(r, p),
    _distribuzione(r, m, p),
    _composizione(r, p),
    _cuore(r, p),
  ];

  List<String> aree(Esito e) =>
      [for (final s in sections) if (s.esito == e) s.title.toLowerCase()];
  final approfondire = aree(Esito.daApprofondire);
  final osservare = aree(Esito.daOsservare);

  String summary;
  if (approfondire.isNotEmpty) {
    summary = 'Emergono segnali in ${_elenco(approfondire)} che meritano un approfondimento';
    if (osservare.isNotEmpty) {
      summary += ', e in ${_elenco(osservare)} da osservare';
    }
    summary += '.';
  } else if (osservare.isNotEmpty) {
    summary = 'Nel complesso il quadro è prevalentemente favorevole, con ${_elenco(osservare)} da osservare.';
  } else {
    summary = 'Nel complesso il quadro è favorevole.';
  }

  String lead;
  if (approfondire.isNotEmpty) {
    lead = 'Le misure del corpo mostrano segnali che meritano un approfondimento, '
        'e da sole non bastano a capirli.';
  } else if (osservare.isNotEmpty) {
    lead = 'Le misure del corpo mostrano alcuni segnali da osservare, ma da sole non ne spiegano la causa.';
  } else {
    lead = 'Le misure del corpo sono una parte del quadro, e qui sono favorevoli.';
  }

  return Comment(
    profilo: p,
    sections: sections,
    summary: summary,
    lifestyle: (approfondire.isNotEmpty || osservare.isNotEmpty) ? _stileDiVita : null,
    ctaLead: lead,
    ctaBody: _ctaBody,
    links: const [
      CtaLink('Stima del rischio cardio-metabolico', kUrlCardio),
      CtaLink('HRV + ASI: Doppia Lettura', kUrlDoppiaLettura),
    ],
    closing: _chiusura,
  );
}
