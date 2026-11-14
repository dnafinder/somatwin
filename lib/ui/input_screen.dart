import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../storage.dart';

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
  /// Ultima misura: precompila sesso, data di nascita e anamnesi.
  final Record? template;

  /// Misura da correggere: precompila tutti i campi e ne mantiene id e data.
  final Record? edit;
  const InputScreen({super.key, this.template, this.edit});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _form = GlobalKey<FormState>();
  final _ctrl = {for (final f in _fields) f.key: TextEditingController()};
  Sex _sex = Sex.male;
  DateTime? _birth;
  bool _anamnesis = false;
  bool _smoker = false;
  int _parents = 0;
  bool _drugs = false;
  String? _birthError;

  @override
  void initState() {
    super.initState();
    final t = widget.edit ?? widget.template;
    if (t != null) {
      _sex = t.m.sex;
      _birth = t.m.birthDate;
      _anamnesis = t.an.answered;
      _smoker = t.an.smoker;
      _parents = t.an.parentsHypertensive;
      _drugs = t.an.onAntihypertensives;
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
        _ctrl[k]!.text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Dati grezzi del soggetto del referto CARDIOMET (maschio, 57 anni).
  void _fillDemo() {
    const v = {
      'weight': '87',
      'height': '173',
      'waist': '107',
      'hip': '103',
      'wrist': '18',
      'neck': '40',
      'calf': '38',
      'sbp': '128',
      'dbp': '87',
      'hr': '61',
    };
    final now = DateTime.now();
    setState(() {
      v.forEach((k, t) => _ctrl[k]!.text = t);
      _sex = Sex.male;
      _birth = DateTime(now.year - 57, 1, 1);
      _birthError = null;
      _anamnesis = true;
      _smoker = false;
      _parents = 1;
      _drugs = false;
    });
    _form.currentState?.validate();
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 40, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Data di nascita',
    );
    if (d != null) setState(() {
      _birth = d;
      _birthError = null;
    });
  }

  double _v(String k) => double.parse(_ctrl[k]!.text.replaceAll(',', '.'));

  void _submit() {
    final okForm = _form.currentState!.validate();
    String? be;
    if (_birth == null) {
      be = 'Obbligatoria';
    } else {
      final now = DateTime.now();
      var age = now.year - _birth!.year;
      if (now.month < _birth!.month || (now.month == _birth!.month && now.day < _birth!.day)) age--;
      if (age < 18) be = 'Solo per adulti (almeno 18 anni)';
    }
    setState(() => _birthError = be);
    if (!okForm || be != null) return;
    if (_v('sbp') <= _v('dbp')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La sistolica deve superare la diastolica.')),
      );
      return;
    }
    final now = DateTime.now();
    final m = Measurements(
      sex: _sex,
      birthDate: _birth!,
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
    Navigator.of(context).pop(Record(widget.edit?.id ?? now.microsecondsSinceEpoch.toString(), m, an));
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
                label: const Text('Demo: dati del referto'),
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<Sex>(
              segments: const [
                ButtonSegment(value: Sex.male, label: Text('Maschio')),
                ButtonSegment(value: Sex.female, label: Text('Femmina')),
              ],
              selected: {_sex},
              onSelectionChanged: (s) => setState(() => _sex = s.first),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickBirth,
              icon: const Icon(Icons.cake_outlined),
              label: Text(_birth == null ? 'Data di nascita' : 'Nato il ${_fmtDate(_birth!)}'),
            ),
            if (_birthError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(_birthError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
            const SizedBox(height: 12),
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
