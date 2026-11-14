import 'package:flutter/material.dart';

import '../core/absi_table.dart';
import '../core/indices.dart';
import '../core/models.dart';
import '../storage.dart';
import '../twin/body_model.dart';
import '../twin/twin_view.dart';
import 'confirm.dart';
import 'input_screen.dart';
import 'theme.dart';

class ResultScreen extends StatefulWidget {
  final Record record;
  final Record? previous;
  final AbsiTable absi;
  const ResultScreen({super.key, required this.record, required this.absi, this.previous});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final Report _report;
  late final Report? _prevReport;
  late final BodyModel _body;
  late final BodyModel? _prevBody;
  String? _selected;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _report = computeReport(r.m, r.an, widget.absi);
    _body = buildBody(r.m);
    final p = widget.previous;
    _prevReport = p == null ? null : computeReport(p.m, p.an, widget.absi);
    _prevBody = p == null ? null : buildBody(p.m);
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
          for (final r in rows) _ResultTile(r),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final fixed = await Navigator.of(context).push<Record>(
      MaterialPageRoute(builder: (_) => InputScreen(edit: widget.record)),
    );
    if (fixed == null || !mounted) return;
    await Storage().update(fixed);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultScreen(record: fixed, previous: widget.previous, absi: widget.absi),
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
      length: hasPrev ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Il tuo Somatwin'),
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
            const Tab(text: 'Twin'),
            const Tab(text: 'Indici'),
            if (hasPrev) const Tab(text: 'Confronto'),
          ]),
        ),
        body: TabBarView(children: [
          _twinTab(),
          _indexTab(),
          if (hasPrev) _compareTab(),
        ]),
      ),
    );
  }

  Widget _twinTab() {
    final legend = Wrap(spacing: 12, runSpacing: 4, children: [
      for (final s in [Severity.ok, Severity.watch, Severity.alert])
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: sevColor(s)),
          const SizedBox(width: 4),
          Text(sevText(s), style: const TextStyle(fontSize: 11)),
        ]),
    ]);
    return Column(children: [
      Expanded(
        child: TwinView(
          model: _body,
          previous: _prevBody,
          severity: _report.body,
          labels: _labels(),
          heartRate: widget.record.m.hr,
          onTapPart: _tap,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          legend,
          const SizedBox(height: 4),
          Text(
            'Anelli pieni: misurati. Tratteggiati: stimati'
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
          for (final r in e.value) _ResultTile(r),
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
        subtitle: Text('prima: ${p.value} ${p.unit}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${r.value} ${r.unit}', style: TextStyle(color: sevColor(r.severity), fontWeight: FontWeight.w600)),
          if (delta.isNotEmpty) Text(delta, style: const TextStyle(fontSize: 11)),
        ]),
      ));
    }
    return ListView(padding: const EdgeInsets.all(12), children: rows);
  }
}

class _ResultTile extends StatelessWidget {
  final IndexResult r;
  const _ResultTile(this.r);

  @override
  Widget build(BuildContext context) {
    final c = sevColor(r.severity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 10, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(r.label)),
            Text('${r.value} ${r.unit}'.trim(), style: TextStyle(color: c, fontWeight: FontWeight.w700)),
          ]),
          if (r.reference.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 18),
              child: Text('Riferimento: ${r.reference}', style: const TextStyle(fontSize: 11)),
            ),
          if (r.comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 18),
              child: Text(r.comment, style: const TextStyle(fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
