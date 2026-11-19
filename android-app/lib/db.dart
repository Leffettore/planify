import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class Db {
  final Database _db;
  Db._(this._db);

  static Future<Db> open() async {
    final db = await openDatabase(
      join(await getDatabasesPath(), 'planify.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE Projects (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT, inbox_project INTEGER)''');
        await db.execute('''CREATE TABLE Items (
          id TEXT PRIMARY KEY, content TEXT NOT NULL, description TEXT, due TEXT,
          project_id TEXT REFERENCES Projects(id) ON DELETE CASCADE, priority INTEGER,
          checked INTEGER, added_at TEXT, completed_at TEXT)''');
        await db.insert('Projects', Project(id: newId(), name: 'Inbox', inbox: true).toMap());
      },
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return Db._(db);
  }

  Future<List<Project>> projects() async =>
      (await _db.query('Projects', orderBy: 'inbox_project DESC, rowid')).map(Project.fromMap).toList();

  Future<List<Item>> items() async => (await _db.query('Items')).map(Item.fromMap).toList();

  // Not INSERT OR REPLACE: that deletes the row first and would cascade-delete its items.
  Future<void> saveProject(Project p) async {
    final n = await _db.update('Projects', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
    if (n == 0) await _db.insert('Projects', p.toMap());
  }

  // Items go with it via ON DELETE CASCADE.
  Future<void> deleteProject(String id) => _db.delete('Projects', where: 'id = ?', whereArgs: [id]);

  Future<void> saveItem(Item i) => _db.insert('Items', i.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteItem(String id) => _db.delete('Items', where: 'id = ?', whereArgs: [id]);
}
