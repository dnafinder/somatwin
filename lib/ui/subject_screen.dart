import 'package:flutter/material.dart';

import '../core/absi_table.dart';
import '../core/models.dart';
import '../storage.dart';
import 'confirm.dart';
import 'input_screen.dart';
import 'result_screen.dart';
import 'theme.dart';

/// Misure di un soggetto del registro, la piu' recente per prima.
class SubjectScreen extends StatefulWidget {
  final Subject subject;
  final AbsiTable absi;
  const SubjectScreen({super.key, required this.subject, required this.absi});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  final _storage = Storage();
  List<Record> _records = [];
  bool _loading = true;

  Subject get _s => widget.subject;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final r = await _storage.load(_s.id);
    if (!mounted) return;
    setState(() {
      _records = r;
      _loading = false;
    });
  }

  Future<void> _new() async {
    final last = _records.isEmpty ? null : _records.first;
    final rec = await Navigator.of(context).push<Record>(
      MaterialPageRoute(builder: (_) => InputScreen(subject: _s, template: last)),
    );
    if (rec == null) return;
    await _storage.add(rec);
    await _reload();
    if (!mounted) return;
    _open(rec);
  }

  Future<void> _open(Record rec) async {
    final idx = _records.indexWhere((r) => r.id == rec.id);
    final prev = (idx >= 0 && idx + 1 < _records.length) ? _records[idx + 1] : null;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultScreen(subject: _s, record: rec, previous: prev, absi: widget.absi),
    ));
    await _reload();
  }

  Future<void> _delete(Record rec) async {
    if (!await confirmDelete(context, fmtDate(rec.m.takenOn))) return;
    await _storage.delete(rec.id);
    await _reload();
  }

  Future<void> _edit(Record rec) async {
    final fixed = await Navigator.of(context).push<Record>(
      MaterialPageRoute(builder: (_) => InputScreen(subject: _s, edit: rec)),
    );
    if (fixed == null) return;
    await _storage.update(fixed);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight * kLabelScale,
        title: Text(_s.fullName),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nuova misura'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nessuna misura per ${_s.fullName}.\nInserisci peso, altezza, circonferenze e pressione per generare il gemello digitale.\n\n$kDisclaimer',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: _records.length,
                  itemBuilder: (context, i) {
                    final r = _records[i];
                    return Dismissible(
                      key: ValueKey(r.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red.shade900,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete),
                      ),
                      confirmDismiss: (_) => confirmDelete(context, fmtDate(r.m.takenOn)),
                      onDismissed: (_) async {
                        await _storage.delete(r.id);
                        await _reload();
                      },
                      child: Card(
                        child: ListTile(
                          title: Text(fmtDate(r.m.takenOn)),
                          subtitle: Text(
                              '${r.m.age} anni, ${r.m.weight.toStringAsFixed(1)} kg, ${r.m.height.toStringAsFixed(0)} cm'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Correggi i dati',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(r),
                              ),
                              IconButton(
                                tooltip: 'Elimina la misura',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(r),
                              ),
                            ],
                          ),
                          onTap: () => _open(r),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
