import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/absi_table.dart';
import '../core/models.dart';
import '../data_io.dart';
import '../share_file.dart';
import '../storage.dart';
import 'confirm.dart';
import 'subject_form.dart';
import 'subject_screen.dart';
import 'theme.dart';

/// Registro dei soggetti. Ogni soggetto ha le sue misure.
class HomeScreen extends StatefulWidget {
  final AbsiTable absi;
  const HomeScreen({super.key, required this.absi});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = Storage();
  List<Subject> _subjects = [];
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await _storage.loadSubjects();
    final c = await _storage.counts();
    if (!mounted) return;
    setState(() {
      _subjects = s;
      _counts = c;
      _loading = false;
    });
  }

  Future<void> _new() async {
    final s = await Navigator.of(context).push<Subject>(
      MaterialPageRoute(builder: (_) => const SubjectFormScreen()),
    );
    if (s == null) return;
    await _storage.addSubject(s);
    await _reload();
    if (!mounted) return;
    _open(s);
  }

  Future<void> _open(Subject s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubjectScreen(subject: s, absi: widget.absi)),
    );
    await _reload();
  }

  Future<void> _edit(Subject s) async {
    final fixed = await Navigator.of(context).push<Subject>(
      MaterialPageRoute(builder: (_) => SubjectFormScreen(edit: s)),
    );
    if (fixed == null) return;
    await _storage.updateSubject(fixed);
    await _reload();
  }

  Future<bool> _confirm(Subject s) {
    return confirmDeleteSubject(context, s.fullName, _counts[s.id] ?? 0);
  }

  Future<void> _delete(Subject s) async {
    if (!await _confirm(s)) return;
    await _storage.deleteSubject(s.id);
    await _reload();
  }

  void _say(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportBackup() async {
    final b = await _storage.loadAll();
    if (b.subjects.isEmpty) {
      _say('Il registro è vuoto: niente da esportare.');
      return;
    }
    try {
      await shareTextFile(backupFileName(DateTime.now()), 'application/json', encodeBackup(b.subjects, b.records));
    } catch (e) {
      if (mounted) _say('Esportazione non riuscita: $e');
    }
  }

  Future<void> _importBackup() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final Backup b;
    try {
      b = decodeBackup(utf8.decode(await f.readAsBytes()));
    } on FormatException catch (e) {
      if (mounted) _say(e.message);
      return;
    }
    final plan = await _storage.importBackup(b, dryRun: true);
    if (!mounted) return;
    if (plan.nothingToAdd) {
      _say('Niente da importare: tutto è già nel registro.');
      return;
    }
    if (!await confirmImport(context, plan)) return;
    final done = await _storage.importBackup(b);
    await _reload();
    if (!mounted) return;
    _say('Importati ${done.subjectsAdded} soggetti e ${done.recordsAdded} misure.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight * kLabelScale,
        title: const Text('Somatwin'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Backup',
            onSelected: (v) => v == 'export' ? _exportBackup() : _importBackup(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Esporta backup (JSON)')),
              PopupMenuItem(value: 'import', child: Text('Importa backup')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuovo soggetto'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _subjects.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Il registro è vuoto.\nAggiungi un soggetto con nome, cognome, sesso e data di nascita, poi associa le sue misure.\n\n$kDisclaimer',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: _subjects.length,
                  itemBuilder: (context, i) {
                    final s = _subjects[i];
                    final n = _counts[s.id] ?? 0;
                    return Dismissible(
                      key: ValueKey(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red.shade900,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete),
                      ),
                      confirmDismiss: (_) => _confirm(s),
                      onDismissed: (_) async {
                        await _storage.deleteSubject(s.id);
                        await _reload();
                      },
                      child: Card(
                        child: ListTile(
                          title: Text(s.fullName),
                          subtitle: Text(
                              '${s.sex.label}, nato il ${fmtDate(s.birth)}, ${n == 1 ? '1 misura' : '$n misure'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Modifica i dati del soggetto',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(s),
                              ),
                              IconButton(
                                tooltip: 'Elimina il soggetto',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(s),
                              ),
                            ],
                          ),
                          onTap: () => _open(s),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
