import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// `dirty` is 0 when a row matches the server, else the time of the last local
/// edit, so sync only marks a row clean if it was not edited while pushing.
int _now() => DateTime.now().microsecondsSinceEpoch;

class Db {
  final Database _db;
  Db._(this._db);

  static Future<void> _v2(DatabaseExecutor db) async {
    // DEFAULT 1: rows from before sync existed get pushed on the first sync.
    await db.execute('ALTER TABLE Projects ADD href TEXT');
    await db.execute('ALTER TABLE Projects ADD dirty INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE Items ADD href TEXT');
    await db.execute('ALTER TABLE Items ADD ical TEXT');
    await db.execute('ALTER TABLE Items ADD dirty INTEGER NOT NULL DEFAULT 1');
    await db.execute('CREATE TABLE Tombstones (href TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE Settings (key TEXT PRIMARY KEY, value TEXT)');
  }

  static Future<Db> open([String? path]) async {
    final db = await openDatabase(
      path ?? join(await getDatabasesPath(), 'planify.db'),
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE Projects (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT, inbox_project INTEGER)''');
        await db.execute('''CREATE TABLE Items (
          id TEXT PRIMARY KEY, content TEXT NOT NULL, description TEXT, due TEXT,
          project_id TEXT REFERENCES Projects(id) ON DELETE CASCADE, priority INTEGER,
          checked INTEGER, added_at TEXT, completed_at TEXT)''');
        await _v2(db);
        await db.insert('Projects', Project(id: newId(), name: 'Inbox', inbox: true).toMap());
      },
      onUpgrade: (db, from, _) async {
        if (from < 2) await _v2(db);
      },
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return Db._(db);
  }

  Future<List<Project>> projects() async =>
      (await _db.query('Projects', orderBy: 'inbox_project DESC, rowid')).map(Project.fromMap).toList();

  Future<List<Item>> items() async => (await _db.query('Items')).map(Item.fromMap).toList();

  // Not INSERT OR REPLACE: that deletes the row first and would cascade-delete its items.
  Future<void> saveProject(Project p, {bool fromServer = false}) async {
    final row = {...p.toMap(), 'dirty': fromServer ? 0 : _now()};
    final n = await _db.update('Projects', row, where: 'id = ?', whereArgs: [p.id]);
    if (n == 0) await _db.insert('Projects', row);
  }

  // Items go with it via ON DELETE CASCADE; deleting the calendar removes them on the server.
  Future<void> deleteProject(String id) => _db.transaction((tx) async {
    await _tombstone(tx, 'Projects', id);
    await tx.delete('Projects', where: 'id = ?', whereArgs: [id]);
  });

  Future<void> saveItem(Item i) => _db.transaction((tx) async {
    final old = await tx.query('Items', columns: ['href', 'project_id'], where: 'id = ?', whereArgs: [i.id]);
    // Moved to another project: it gets a new resource in that calendar.
    if (old.isNotEmpty && old.first['project_id'] != i.projectId && old.first['href'] != null) {
      await tx.insert('Tombstones', {'href': old.first['href']}, conflictAlgorithm: ConflictAlgorithm.ignore);
      i.href = null;
    }
    await tx.insert('Items', {...i.toMap(), 'dirty': _now()}, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<void> deleteItem(String id) => _db.transaction((tx) async {
    await _tombstone(tx, 'Items', id);
    await tx.delete('Items', where: 'id = ?', whereArgs: [id]);
  });

  Future<void> _tombstone(Transaction tx, String table, String id) async {
    final href = (await tx.query(table, columns: ['href'], where: 'id = ?', whereArgs: [id])).firstOrNull?['href'];
    if (href != null) await tx.insert('Tombstones', {'href': href}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // --- Sync ---------------------------------------------------------------

  Future<String?> setting(String key) async =>
      (await _db.query('Settings', where: 'key = ?', whereArgs: [key])).firstOrNull?['value'] as String?;

  Future<void> setSetting(String key, String value) =>
      _db.insert('Settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<String>> tombstones() async => (await _db.query('Tombstones')).map((r) => r['href'] as String).toList();

  Future<void> dropTombstone(String href) => _db.delete('Tombstones', where: 'href = ?', whereArgs: [href]);

  Future<List<(Project, int)>> dirtyProjects() async =>
      (await _db.query('Projects', where: 'dirty != 0')).map((r) => (Project.fromMap(r), r['dirty'] as int)).toList();

  Future<List<(Item, int)>> dirtyItems() async =>
      (await _db.query('Items', where: 'dirty != 0')).map((r) => (Item.fromMap(r), r['dirty'] as int)).toList();

  Future<void> markPushed(String table, String id, int dirty, Map<String, Object?> values) =>
      _db.update(table, {...values, 'dirty': 0}, where: 'id = ? AND dirty = ?', whereArgs: [id, dirty]);

  /// Replaces clean local data with the server's. Rows edited locally since the
  /// push (dirty) are left alone and go up on the next sync.
  Future<void> applyPull(List<Project> projects, List<Item> items) => _db.transaction((tx) async {
    final hrefs = {for (final p in projects) p.href};
    for (final p in await tx.query('Projects', where: 'href IS NOT NULL AND dirty = 0')) {
      if (hrefs.contains(p['href'])) continue;
      if (p['inbox_project'] == 1) {
        // Deleted on the server: never drop the inbox, re-create it there instead.
        await tx.update('Projects', {'href': null, 'dirty': _now()}, where: 'id = ?', whereArgs: [p['id']]);
        await tx.update('Items', {'href': null, 'dirty': _now()}, where: 'project_id = ?', whereArgs: [p['id']]);
      } else {
        await tx.delete('Projects', where: 'id = ?', whereArgs: [p['id']]);
      }
    }
    for (final p in projects) {
      final row = {'name': p.name, 'color': p.color, 'href': p.href, 'dirty': 0};
      final local = await tx.query('Projects', where: 'href = ?', whereArgs: [p.href]);
      if (local.isEmpty) {
        await tx.insert('Projects', {...p.toMap(), 'dirty': 0});
      } else if (local.first['dirty'] == 0) {
        await tx.update('Projects', row, where: 'href = ?', whereArgs: [p.href]);
      }
    }
    final itemHrefs = {for (final i in items) i.href};
    for (final r in await tx.query('Items', columns: ['id', 'href'], where: 'href IS NOT NULL AND dirty = 0')) {
      if (!itemHrefs.contains(r['href'])) await tx.delete('Items', where: 'id = ?', whereArgs: [r['id']]);
    }
    for (final i in items) {
      final local = await tx.query('Items', columns: ['dirty'], where: 'id = ?', whereArgs: [i.id]);
      if (local.isEmpty || local.first['dirty'] == 0) {
        await tx.insert('Items', {...i.toMap(), 'dirty': 0}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  });
}
