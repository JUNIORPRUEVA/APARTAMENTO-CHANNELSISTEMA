import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('sqlite3 nativo disponible (memoria, PRAGMA y constraint)', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);

    expect(sqlite3.version.libVersion, isNotEmpty);

    db.execute('PRAGMA foreign_keys = ON;');
    db.execute(
      'CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);',
    );
    db.execute("INSERT INTO t (name) VALUES ('a');");

    expect(db.select('SELECT COUNT(*) AS c FROM t;').first['c'], 1);
    expect(
      () => db.execute("INSERT INTO t (name) VALUES ('a');"),
      throwsA(isA<SqliteException>()),
    );
    // ignore: avoid_print
    print('SQLITE_VERSION=${sqlite3.version.libVersion}');
  });
}
