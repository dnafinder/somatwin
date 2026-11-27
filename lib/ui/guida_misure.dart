import 'package:flutter/material.dart';

import '../core/models.dart';
import '../twin/mh_body.dart';
import '../twin/mh_data.dart';
import '../twin/mh_view.dart';

/// Colore con cui la guida accende il distretto da misurare. Non ha un
/// significato clinico: i colori della scheda Twin restano quelli delle zone.
const Color kGuideColor = Color(0xFFB388FF);

class _Step {
  final String title;
  final String text;

  /// Distretto del twin da accendere ('neck', 'waist', 'hip', 'wrist', 'calf',
  /// 'heart'). Null: corpo intero senza evidenziazioni.
  final String? tag;
  final double zoom;
  const _Step(this.title, this.text, this.tag, this.zoom);
}

const List<_Step> kGuideSteps = [
  _Step(
    'Altezza',
    'Scalzo, con talloni, glutei e spalle contro la parete e lo sguardo in avanti. '
        'Squadra appoggiata sulla testa, lettura dopo un\'inspirazione profonda.',
    null,
    1.0,
  ),
  _Step(
    'Collo',
    'Metro appena sotto la prominenza della laringe (il pomo d\'Adamo), perpendicolare '
        'all\'asse del collo. Testa dritta, spalle rilassate.',
    'neck',
    2.8,
  ),
  _Step(
    'Vita',
    'Nel punto più stretto del tronco, tra l\'ultima costola e l\'osso del fianco. In piedi, a fine '
        'espirazione normale, con il metro orizzontale a contatto con la pelle, senza stringere.',
    'waist',
    1.9,
  ),
  _Step(
    'Fianchi',
    'Dove i glutei sporgono di più, visti di lato. Piedi uniti, metro orizzontale, su indumenti sottili.',
    'hip',
    1.9,
  ),
  _Step(
    'Polso',
    'Subito sopra le due sporgenze ossee del polso (processi stiloidei), dal lato dell\'avambraccio. '
        'Braccio rilassato, sempre lo stesso lato.',
    'wrist',
    2.6,
  ),
  _Step(
    'Polpaccio',
    'Alla massima circonferenza, trovata spostando il metro su e giù. In piedi, con il peso '
        'ripartito sulle due gambe, sempre lo stesso lato.',
    'calf',
    2.2,
  ),
  _Step(
    'Peso',
    'Al mattino, a digiuno, dopo aver urinato, senza scarpe e con pochi vestiti.',
    null,
    1.0,
  ),
  _Step(
    'Pressione',
    'Seduto, con la schiena appoggiata e i piedi a terra non incrociati, dopo 5 minuti di riposo. '
        'Braccio nudo appoggiato a livello del cuore, bracciale della misura giusta. Niente caffè, '
        'fumo o sport nella mezz\'ora prima. Meglio due misure a 1-2 minuti l\'una dall\'altra, da mediare.',
    'heart',
    2.2,
  ),
  _Step(
    'Frequenza',
    'A riposo, seduto, dopo gli stessi 5 minuti. Dal misuratore di pressione o contando i battiti per 60 secondi.',
    'heart',
    2.2,
  ),
];

/// Centro della vista per un distretto: media dei punti della sezione (o il
/// cuore). Null per il corpo intero.
List<double>? guideFocus(MhBody body, String? tag) {
  if (tag == null) return null;
  if (tag == 'heart') return List<double>.of(body.heart);
  final polys = body.rings[tag];
  if (polys == null || polys.isEmpty) return null;
  final p = polys.first;
  final n = p.length ~/ 3;
  if (n == 0) return null;
  var x = 0.0, y = 0.0, z = 0.0;
  for (var i = 0; i < n; i++) {
    x += p[i * 3];
    y += p[i * 3 + 1];
    z += p[i * 3 + 2];
  }
  return [x / n, y / n, z / n];
}

/// Guida alle misure: una sezione per volta, con il twin che accende il
/// distretto interessato. Il corpo e' quello di un soggetto inventato.
class MeasureGuideScreen extends StatefulWidget {
  const MeasureGuideScreen({super.key});

  @override
  State<MeasureGuideScreen> createState() => _MeasureGuideScreenState();
}

class _MeasureGuideScreenState extends State<MeasureGuideScreen> {
  MhBody? _body;
  bool _failed = false;
  int _i = 0;

  static final Measurements _sample = Measurements(
    sex: Sex.male,
    birthDate: DateTime(1985, 1, 1),
    takenOn: DateTime(2026, 1, 1),
    weight: 76,
    height: 176,
    waist: 90,
    hip: 98,
    wrist: 17.5,
    neck: 38,
    calf: 37,
    sbp: 122,
    dbp: 78,
    hr: 68,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await MhData.shared();
      final body = MhBody.build(data, _sample);
      if (mounted) setState(() => _body = body);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _twin(_Step s) {
    final body = _body;
    if (body == null) {
      return Center(
        child: _failed
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Il modello del corpo non si carica: restano le istruzioni scritte.'),
              )
            : const CircularProgressIndicator(),
      );
    }
    final tag = s.tag;
    return MhTwinView(
      key: ValueKey(_i),
      body: body,
      colors: tag == null ? const {} : {tag: kGuideColor},
      labels: tag == null ? const {} : {tag: s.title},
      heartRate: _sample.hr,
      focus: guideFocus(body, tag),
      initialZoom: s.zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = kGuideSteps[_i];
    return Scaffold(
      appBar: AppBar(title: const Text('Come si prendono le misure')),
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: kGuideSteps.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, k) => ChoiceChip(
                label: Text(kGuideSteps[k].title),
                selected: k == _i,
                onSelected: (_) => setState(() => _i = k),
              ),
            ),
          ),
          Expanded(flex: 5, child: _twin(s)),
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_i + 1}. ${s.title}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(s.text),
                const SizedBox(height: 6),
                const Text(
                  'Il corpo è quello di un soggetto di esempio, non il tuo.',
                  style: TextStyle(fontSize: 11),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              TextButton(onPressed: _i == 0 ? null : () => setState(() => _i--), child: const Text('Indietro')),
              Expanded(
                child: Text('${_i + 1} di ${kGuideSteps.length}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ),
              TextButton(
                  onPressed: _i == kGuideSteps.length - 1 ? null : () => setState(() => _i++),
                  child: const Text('Avanti')),
            ]),
          ),
        ]),
      ),
    );
  }
}
