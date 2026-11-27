import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../core/absi_table.dart';
import '../core/commento.dart';
import '../core/indices.dart';
import '../core/models.dart';
import '../storage.dart';
import '../twin/body_model.dart';
import '../twin/mh_body.dart';
import '../twin/mh_data.dart';
import '../twin/mh_view.dart';
import '../twin/twin_view.dart';
import 'confirm.dart';
import 'input_screen.dart';
import 'range_bar.dart';
import 'theme.dart';

class ResultScreen extends StatefulWidget {
  final Subject subject;
  final Record record;
  final Record? previous;
  final AbsiTable absi;
  const ResultScreen({super.key, required this.subject, required this.record, required this.absi, this.previous});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final Report _report;
  late final Comment _comment;
  late final Report? _prevReport;
  late final BodyModel _body;
  late final BodyModel? _prevBody;
  late final Map<String, Color> _bodyColors;
  MhBody? _mhBody;
  MhBody? _mhPrev;
  bool _mhFailed = false;
  String? _selected;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _report = computeReport(r.m, r.an, widget.absi);
    _comment = buildComment(_report, r.m);
    _body = buildBody(r.m);
    final p = widget.previous;
    _prevReport = p == null ? null : computeReport(p.m, p.an, widget.absi);
    _prevBody = p == null ? null : buildBody(p.m);
    _bodyColors = _zoneColors();
    _loadMh();
  }

  /// Costruisce il corpo MakeHuman fuori dal primo frame. In caso di errore
  /// resta il modello a sezioni.
  Future<void> _loadMh() async {
    try {
      final data = await MhData.shared();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final now = MhBody.build(data, widget.record.m);
      if (!mounted) return;
      setState(() => _mhBody = now);
      final p = widget.previous;
      if (p != null) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final prev = MhBody.build(data, p.m);
        if (!mounted) return;
        setState(() => _mhPrev = prev);
      }
    } catch (e) {
      if (mounted) setState(() => _mhFailed = true);
    }
  }

  /// Colore di ogni distretto = zona della barra dei suoi indici. Con piu'
  /// indici vince la zona peggiore: sopra la norma, poi sotto, poi nella norma.
  /// Il polso non ha una barra e resta neutro.
  Map<String, Color> _zoneColors() {
    final out = <String, Color>{};
    int rank(int z) => z > 0 ? 2 : (z < 0 ? 1 : 0);
    int? zoneOf(String key) {
      final r = _report.byKey(key);
      if (r == null) return null;
      final v = _report.values[key] ?? double.tryParse(r.value);
      final c = zoneColor(r.reference, v);
      if (c == null) return null;
      return c == kBarBlue ? -1 : (c == kBarRed ? 1 : 0);
    }

    _partKeys.forEach((tag, keys) {
      int? worst;
      void take(int? z) {
        if (z == null) return;
        if (worst == null || rank(z) > rank(worst!)) worst = z;
      }

      for (final k in keys) {
        take(k == 'BP' ? (_report.values['BPZONE'] ?? 0).round() : zoneOf(k));
      }
      if (worst != null) out[tag] = zoneColorOf(worst!);
    });
    // Vita: conta solo la circonferenza (94 cm uomini, 80 donne). Gli indici
    // composti restano nella scheda Indici. Fianchi: nessun riferimento di
    // rischio per la sola circonferenza, il distretto resta neutro.
    out['waist'] = waistRaised(widget.record.m) ? kBarRed : kBarGreen;
    // Cuore: l'etichetta mostra i battiti, quindi il colore segue solo la
    // frequenza a riposo. Pressione e indici derivati restano nella scheda Indici.
    // Collo: colore dal punteggio STOP-BANG (0-2 verde, 3-4 arancio, 5-8 rosso).
    // Senza questionario il collo resta neutro.
    final sb = _report.values['STOPBANG'];
    if (sb == null) {
      out.remove('neck');
    } else {
      out['neck'] = sb >= 5 ? kBarRed : (sb >= 3 ? kBarOrange : kBarGreen);
    }
    out['heart'] = zoneColorOf((_report.values['HRZONE'] ?? 0).round());
    out.remove('hip');
    return out;
  }

  Map<String, String> _labels() {
    final m = widget.record.m;
    return {
      'neck': 'Collo ${m.neck.toStringAsFixed(0)} cm',
      'waist': 'Vita ${m.waist.toStringAsFixed(0)} cm',
      'hip': 'Fianchi ${m.hip.toStringAsFixed(0)} cm',
      'wrist': 'Polso ${m.wrist.toStringAsFixed(1)} cm',
      'calf': 'Polpaccio ${m.calf.toStringAsFixed(0)} cm',
      'heart': '${m.hr.toStringAsFixed(0)} bpm',
    };
  }

  /// Indici che spiegano ogni distretto toccato nel modello.
  static const _partKeys = {
    'neck': ['NECK'],
    'waist': ['WHR', 'WHTR', 'AVI', 'ABSI_Z', 'BRI', 'CI'],
    'hip': ['WHR', 'BAI'],
    'wrist': ['GRANT'],
    'calf': ['CALFCORR'],
    'heart': ['BP', 'HR', 'HRR', 'MAP', 'PP', 'RPP', 'MSI', 'EPWV'],
  };

  void _tap(String tag) {
    setState(() => _selected = tag);
    final keys = _partKeys[tag] ?? const <String>[];
    final rows = <IndexResult>[
      for (final r in _report.results)
        if (keys.contains(r.key)) r,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shrinkWrap: true,
        children: [
          Text(_labels()[tag] ?? tag, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (rows.isEmpty) const Text('Nessun indice collegato.'),
          for (final r in rows) _ResultTile(r, _report.values[r.key], _report.values),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final fixed = await Navigator.of(context).push<Record>(
      MaterialPageRoute(builder: (_) => InputScreen(subject: widget.subject, edit: widget.record)),
    );
    if (fixed == null || !mounted) return;
    await Storage().update(fixed);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultScreen(subject: widget.subject, record: fixed, previous: widget.previous, absi: widget.absi),
    ));
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, fmtDate(widget.record.m.takenOn))) return;
    await Storage().delete(widget.record.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasPrev = _prevReport != null;
    return DefaultTabController(
      length: hasPrev ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: kToolbarHeight * kLabelScale,
          title: Text(widget.subject.fullName),
          actions: [
            IconButton(
              tooltip: 'Correggi i dati',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
            IconButton(
              tooltip: 'Elimina la misura',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(height: 46 * kLabelScale, text: 'Twin'),
            Tab(height: 46 * kLabelScale, text: 'Indici'),
            Tab(height: 46 * kLabelScale, text: 'Commento'),
            if (hasPrev) Tab(height: 46 * kLabelScale, text: 'Confronto'),
          ]),
        ),
        body: TabBarView(children: [
          _twinTab(),
          _indexTab(),
          _commentTab(),
          if (hasPrev) _compareTab(),
        ]),
      ),
    );
  }

  Widget _twinTab() {
    final legend = Wrap(spacing: 12, runSpacing: 4, children: [
      for (final e in const [
        (kBarBlue, 'Sotto la norma'),
        (kBarGreen, 'Nella norma'),
        (kBarRed, 'Sopra la norma'),
      ])
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: e.$1),
          const SizedBox(width: 4),
          Text(e.$2, style: const TextStyle(fontSize: 11)),
        ]),
    ]);
    return Column(children: [
      Expanded(
        child: _mhBody != null
            ? MhTwinView(
                body: _mhBody!,
                previous: widget.previous == null ? null : _mhPrev,
                colors: _bodyColors,
                labels: _labels(),
                heartRate: widget.record.m.hr,
                onTapPart: _tap,
              )
            : _mhFailed
                ? TwinView(
                    model: _body,
                    previous: _prevBody,
                    severity: _report.body,
                    labels: _labels(),
                    heartRate: widget.record.m.hr,
                    onTapPart: _tap,
                  )
                : const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Costruzione del modello'),
                    ]),
                  ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          legend,
          const SizedBox(height: 4),
          Text(
            _mhBody != null
                ? 'Il corpo rispetta altezza, collo, vita, fianchi, polpaccio e polso misurati.'
                    '${_mhBody!.fit.volumeFitted ? '' : ' Il volume resta sotto il peso rilevato.'}'
                    '${_mhPrev != null ? ' In grigio: misura precedente.' : ''}'
                : 'Anelli pieni: misurati. Tratteggiati: stimati'
                    '${_body.volumeFitted ? '' : ' (peso e misure poco coerenti)'}.'
                    '${_prevBody != null ? ' In grigio: misura precedente.' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
        ]),
      ),
    ]);
  }

  Widget _indexTab() {
    final groups = <String, List<IndexResult>>{};
    for (final r in _report.results) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(e.key, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final r in e.value) _ResultTile(r, _report.values[r.key], _report.values),
        ],
        if (_report.zonesFcmax.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text('Zone di frequenza cardiaca', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final z in _report.zonesKarvonen)
            ListTile(dense: true, title: Text(z.label), trailing: Text(z.range)),
        ],
        for (final n in _report.notes)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(n, style: const TextStyle(fontSize: 12))),
        const SizedBox(height: 16),
        Text(kDisclaimer, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Non riesco ad aprire il link.')),
    );
  }

  Widget _commentTab() {
    final c = _comment;
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final s in c.sections)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s.title, style: theme.textTheme.titleMedium)),
                  Text(s.esito.label,
                      style: TextStyle(
                          color: sevColor(s.esito.severity), fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text(s.text, style: body),
              ]),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('In sintesi', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(c.summary, style: body),
              if (c.lifestyle != null) ...[
                const SizedBox(height: 8),
                Text(c.lifestyle!, style: body),
              ],
            ]),
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.ctaLead, style: body?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(c.ctaBody, style: body),
              const SizedBox(height: 12),
              for (final l in c.links)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(onPressed: () => _open(l.url), child: Text(l.label)),
                  ),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: Text(c.closing, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _compareTab() {
    final prev = _prevReport!;
    final rows = <Widget>[];
    for (final r in _report.results) {
      final p = prev.byKey(r.key);
      if (p == null) continue;
      final a = _report.values[r.key];
      final b = prev.values[r.key];
      String delta = '';
      if (a != null && b != null) {
        final d = a - b;
        delta = '${d >= 0 ? '+' : ''}${d.toStringAsFixed(2)}';
      }
      rows.add(ListTile(
        dense: true,
        title: Text(r.label),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('prima: ${p.value} ${p.unit}'),
          _under(r, a, _report.values),
        ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${r.value} ${r.unit}',
              style: TextStyle(
                  color: _valueColor(r, a, _report.values),
                  fontWeight: FontWeight.w600)),
          if (delta.isNotEmpty) Text(delta, style: const TextStyle(fontSize: 11)),
        ]),
      ));
    }
    return ListView(padding: const EdgeInsets.all(12), children: rows);
  }
}

/// Colore di un rischio rispetto al profilo ottimale: verde, giallo, rosso.
Color _riskColor(Severity sv) {
  switch (sv) {
    case Severity.ok:
      return kBarGreen;
    case Severity.watch:
      return sevColor(Severity.watch);
    case Severity.alert:
      return kBarRed;
    case Severity.info:
      return kWireColor;
  }
}

/// Colore del valore: la zona della barra; per la pressione la zona a tre stati.
Color _valueColor(IndexResult r, double? value, Map<String, double> values) {
  if (r.key == 'BP') return zoneColorOf((values['BPZONE'] ?? 0).round());
  if (r.key.startsWith('HT')) return _riskColor(r.severity);
  final gv = value ?? double.tryParse(r.value);
  if (r.grades.isNotEmpty && gv != null) return gradeColor(r.grades, gv);
  return zoneColor(r.reference, value ?? double.tryParse(r.value)) ?? sevColor(r.severity);
}

/// Sotto il valore: barra di riferimento. Pressione, frequenza e Grant
/// aggiungono lo stato in parole (la pressione non ha una barra).
Widget _under(IndexResult r, double? value, Map<String, double> values) {
  final bar = RangeBar(reference: r.reference, grades: r.grades, value: value ?? double.tryParse(r.value));
  switch (r.key) {
    case 'GRANT':
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(r.comment, style: const TextStyle(fontSize: 13)),
      );
    case 'HT1':
    case 'HT2':
    case 'HT4':
      final y = r.key.substring(2);
      final ideal = values['HTREF$y'];
      final mult = values['HTX$y'];
      if (ideal == null || mult == null) return const SizedBox.shrink();
      final c = _riskColor(r.severity);
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13), children: [
          TextSpan(text: 'Profilo ottimale ${ideal.toStringAsFixed(2)} %  \u00b7  '),
          TextSpan(
              text: '${mult.toStringAsFixed(1)} volte',
              style: TextStyle(color: c, fontWeight: FontWeight.w700)),
        ])),
      );
    case 'BP':
    case 'HR':
      final z = (values[r.key == 'BP' ? 'BPZONE' : 'HRZONE'] ?? 0).round();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(r.comment,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: zoneColorOf(z))),
        ),
        bar,
      ]);
  }
  return bar;
}

class _ResultTile extends StatelessWidget {
  final IndexResult r;
  final double? value;
  final Map<String, double> values;
  const _ResultTile(this.r, this.value, this.values);

  @override
  Widget build(BuildContext context) {
    final c = _valueColor(r, value, values);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.label)),
            Text('${r.value} ${r.unit}'.trim(), style: TextStyle(color: c, fontWeight: FontWeight.w700)),
          ]),
          _under(r, value, values),
        ]),
      ),
    );
  }
}
