import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../storage.dart';
import 'confirm.dart' show fmtDate;

class _Field {
  final String key;
  final String label;
  final String unit;
  final double min;
  final double max;
  const _Field(this.key, this.label, this.unit, this.min, this.max);
}

const _fields = [
  _Field('weight', 'Peso', 'kg', 30, 300),
  _Field('height', 'Altezza', 'cm', 120, 220),
  _Field('waist', 'Vita', 'cm', 40, 200),
  _Field('hip', 'Fianchi', 'cm', 50, 200),
  _Field('wrist', 'Polso', 'cm', 10, 30),
  _Field('neck', 'Collo', 'cm', 20, 70),
  _Field('calf', 'Polpaccio', 'cm', 15, 70),
  _Field('sbp', 'Pressione sistolica', 'mmHg', 60, 260),
  _Field('dbp', 'Pressione diastolica', 'mmHg', 30, 160),
  _Field('hr', 'Frequenza cardiaca', 'bpm', 30, 200),
];

class InputScreen extends StatefulWidget {
  /// Soggetto del registro: sesso e data di nascita vengono da qui.
  final Subject subject;

  /// Ultima misura del soggetto: precompila l'anamnesi, l'altezza, il polso e il collo.
  final Record? template;

  /// Misura da correggere: precompila tutti i campi e ne mantiene id e data.
  final Record? edit;
  const InputScreen({super.key, required this.subject, this.template, this.edit});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _form = GlobalKey<FormState>();
  final _ctrl = {for (final f in _fields) f.key: TextEditingController()};
  bool _anamnesis = false;
  bool _smoker = false;
  int _parents = 0;
  bool _drugs = false;

  @override
  void initState() {
    super.initState();
    final t = widget.edit ?? widget.template;
    if (t != null) {
      _anamnesis = t.an.answered;
      _smoker = t.an.smoker;
      _parents = t.an.parentsHypertensive;
      _drugs = t.an.onAntihypertensives;
    }
    // Nuova misura di un soggetto gia' misurato: altezza, polso e collo non
    // cambiano da una visita all'altra, quindi si precompilano dall'ultima.
    // Restano modificabili.
    final prev = widget.template;
    if (widget.edit == null && prev != null) {
      for (final e in {'height': prev.m.height, 'wrist': prev.m.wrist, 'neck': prev.m.neck}.entries) {
        _ctrl[e.key]!.text = _fmt(e.value);
      }
    }
    final e = widget.edit;
    if (e != null) {
      final m = e.m;
      final vals = {
        'weight': m.weight,
        'height': m.height,
        'waist': m.waist,
        'hip': m.hip,
        'wrist': m.wrist,
        'neck': m.neck,
        'calf': m.calf,
        'sbp': m.sbp,
        'dbp': m.dbp,
        'hr': m.hr,
      };
      vals.forEach((k, v) {
        _ctrl[k]!.text = _fmt(v);
      });
    }
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Misure di prova di un soggetto inventato.
  void _fillDemo() {
    const v = {
      'weight': '76',
      'height': '176',
      'waist': '90',
      'hip': '98',
      'wrist': '17.5',
      'neck': '38',
      'calf': '37',
      'sbp': '122',
      'dbp': '78',
      'hr': '68',
    };
    setState(() {
      v.forEach((k, t) => _ctrl[k]!.text = t);
      _anamnesis = true;
      _smoker = false;
      _parents = 1;
      _drugs = false;
    });
    _form.currentState?.validate();
  }

  double _v(String k) => double.parse(_ctrl[k]!.text.replaceAll(',', '.'));

  void _submit() {
    final okForm = _form.currentState!.validate();
    if (!okForm) return;
    if (_v('sbp') <= _v('dbp')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La sistolica deve superare la diastolica.')),
      );
      return;
    }
    final now = DateTime.now();
    final m = Measurements(
      sex: widget.subject.sex,
      birthDate: widget.subject.birth,
      takenOn: widget.edit?.m.takenOn ?? now,
      weight: _v('weight'),
      height: _v('height'),
      waist: _v('waist'),
      hip: _v('hip'),
      wrist: _v('wrist'),
      neck: _v('neck'),
      calf: _v('calf'),
      sbp: _v('sbp'),
      dbp: _v('dbp'),
      hr: _v('hr'),
    );
    final an = Anamnesis(
      answered: _anamnesis,
      smoker: _anamnesis && _smoker,
      parentsHypertensive: _anamnesis ? _parents : 0,
      onAntihypertensives: _anamnesis && _drugs,
    );
    Navigator.of(context).pop(Record(widget.edit?.id ?? now.microsecondsSinceEpoch.toString(), m, an,
        subjectId: widget.subject.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.edit == null ? 'Nuova misura' : 'Correggi la misura')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.edit == null) ...[
              OutlinedButton.icon(
                onPressed: _fillDemo,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Demo'),
              ),
              const SizedBox(height: 12),
            ],
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${widget.subject.fullName}, ${widget.subject.sex.label.toLowerCase()}, nato il ${fmtDate(widget.subject.birth)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final f in _fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextFormField(
                  controller: _ctrl[f.key],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(
                    labelText: f.label,
                    suffixText: f.unit,
                    helperText: 'Da ${f.min.toStringAsFixed(0)} a ${f.max.toStringAsFixed(0)}',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (s) {
                    final v = double.tryParse((s ?? '').replaceAll(',', '.'));
                    if (v == null) return 'Valore mancante';
                    if (v < f.min || v > f.max) return 'Fuori intervallo (${f.min.toStringAsFixed(0)}-${f.max.toStringAsFixed(0)})';
                    return null;
                  },
                ),
              ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aggiungi anamnesi (facoltativa)'),
              subtitle: const Text('Serve solo al rischio di ipertensione a 1, 2 e 4 anni.'),
              value: _anamnesis,
              onChanged: (v) => setState(() => _anamnesis = v),
            ),
            if (_anamnesis) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fumatore'),
                value: _smoker,
                onChanged: (v) => setState(() => _smoker = v),
              ),
              Row(children: [
                const Expanded(child: Text('Genitori ipertesi')),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('0')),
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 2, label: Text('2')),
                  ],
                  selected: {_parents},
                  onSelectionChanged: (s) => setState(() => _parents = s.first),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('In terapia antipertensiva'),
                value: _drugs,
                onChanged: (v) => setState(() => _drugs = v),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.accessibility_new),
              label: Text(widget.edit == null ? 'Genera il gemello digitale' : 'Salva la correzione'),
            ),
          ],
        ),
      ),
    );
  }
}
