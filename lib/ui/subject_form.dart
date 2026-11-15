import 'package:flutter/material.dart';

import '../core/models.dart';
import '../storage.dart';

/// Scheda anagrafica del registro: nome, cognome, sesso e data di nascita.
/// Sono i dati che non cambiano da una misura all'altra.
class SubjectFormScreen extends StatefulWidget {
  final Subject? edit;
  const SubjectFormScreen({super.key, this.edit});

  @override
  State<SubjectFormScreen> createState() => _SubjectFormScreenState();
}

class _SubjectFormScreenState extends State<SubjectFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  Sex _sex = Sex.male;
  DateTime? _birth;
  String? _birthError;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _name.text = e.name;
      _surname.text = e.surname;
      _sex = e.sex;
      _birth = e.birth;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    super.dispose();
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
    if (d != null) {
      setState(() {
        _birth = d;
        _birthError = null;
      });
    }
  }

  static String? birthProblem(DateTime? birth, DateTime now) {
    if (birth == null) return 'Obbligatoria';
    var age = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
    return age < 18 ? 'Solo per adulti (almeno 18 anni)' : null;
  }

  void _submit() {
    final ok = _form.currentState!.validate();
    final be = birthProblem(_birth, DateTime.now());
    setState(() => _birthError = be);
    if (!ok || be != null) return;
    final id = widget.edit?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    Navigator.of(context).pop(Subject(
      id: id,
      name: _name.text.trim(),
      surname: _surname.text.trim(),
      sex: _sex,
      birth: _birth!,
    ));
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String? _required(String? s) => (s == null || s.trim().isEmpty) ? 'Obbligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.edit == null ? 'Nuovo soggetto' : 'Dati del soggetto')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _surname,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Cognome', border: OutlineInputBorder()),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
              validator: _required,
            ),
            const SizedBox(height: 16),
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
              label: Text(_birth == null ? 'Data di nascita' : 'Nato il ${_fmt(_birth!)}'),
            ),
            if (_birthError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(_birthError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
            if (widget.edit != null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Sesso e data di nascita valgono per tutte le misure di questo soggetto.',
                    style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: Text(widget.edit == null ? 'Aggiungi al registro' : 'Salva'),
            ),
          ],
        ),
      ),
    );
  }
}
