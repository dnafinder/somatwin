import 'package:flutter/material.dart';

import '../core/absi_table.dart';
import '../core/models.dart';
import '../storage.dart';
import 'input_screen.dart';
import 'result_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  final AbsiTable absi;
  const HomeScreen({super.key, required this.absi});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = Storage();
  List<Record> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final r = await _storage.load();
    if (!mounted) return;
    setState(() {
      _records = r;
      _loading = false;
    });
  }

  Future<void> _new() async {
    final last = _records.isEmpty ? null : _records.first;
    final rec = await Navigator.of(context).push<Record>(
      MaterialPageRoute(builder: (_) => InputScreen(template: last)),
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
      builder: (_) => ResultScreen(record: rec, previous: prev, absi: widget.absi),
    ));
    await _reload();
  }

  Future<void> _edit(Record rec) async {
    final fixed = await Navigator.of(context).push<Record>(
      MaterialPageRoute(builder: (_) => InputScreen(edit: rec)),
    );
    if (fixed == null) return;
    await _storage.update(fixed);
    await _reload();
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Somatwin')),
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
                      'Nessuna misura salvata.\nInserisci peso, altezza, circonferenze e pressione per generare il tuo gemello digitale.\n\n$kDisclaimer',
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
                      confirmDismiss: (_) async =>
                          await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Eliminare la misura?'),
                              content: const Text('L\'operazione non si puo\' annullare.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
                                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Elimina')),
                              ],
                            ),
                          ) ??
                          false,
                      onDismissed: (_) async {
                        await _storage.delete(r.id);
                        await _reload();
                      },
                      child: Card(
                        child: ListTile(
                          title: Text(_date(r.m.takenOn)),
                          subtitle: Text(
                              '${r.m.sex.label}, ${r.m.age} anni, ${r.m.weight.toStringAsFixed(1)} kg, ${r.m.height.toStringAsFixed(0)} cm'),
                          trailing: IconButton(
                            tooltip: 'Correggi i dati',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(r),
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
