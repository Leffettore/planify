import 'package:flutter_test/flutter_test.dart';
import 'package:planify/ical.dart';
import 'package:planify/models.dart';

void main() {
  // Shaped like what Planify desktop writes (timezone, subtask link, alarm, labels).
  const desktop = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Planify//EN\r\n'
      'BEGIN:VTIMEZONE\r\nTZID:Europe/Rome\r\nLAST-MODIFIED:20200101T000000Z\r\nEND:VTIMEZONE\r\n'
      'BEGIN:VTODO\r\nUID:abc\r\nSUMMARY:Buy milk\\, eggs\r\nDESCRIPTION:line1\\nline2\r\n'
      'DUE;TZID=Europe/Rome:20261120T183000\r\nPRIORITY:5\r\nSTATUS:NEEDS-ACTION\r\n'
      'RELATED-TO;RELTYPE=PARENT:parent-1\r\nCATEGORIES:home\r\nX-APPLE-SORT-ORDER:42\r\n'
      'BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Reminder\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\n'
      'END:VTODO\r\nEND:VCALENDAR\r\n';

  test('parses desktop tasks', () {
    final i = itemFromIcs(desktop, 'p')!;
    expect(i.id, 'abc');
    expect(i.content, 'Buy milk, eggs');
    expect(i.description, 'line1\nline2');
    expect(i.due, DateTime(2026, 11, 20));
    expect(i.priority, 3); // ical 5 = P2
    expect(i.checked, false);
  });

  test('writing back keeps fields this app does not edit', () {
    final i = itemFromIcs(desktop, 'p')!
      ..content = 'Buy bread'
      ..checked = true
      ..completedAt = DateTime.utc(2026, 11, 19, 10);
    final out = itemToIcs(i);
    for (final keep in [
      'RELATED-TO;RELTYPE=PARENT:parent-1', 'CATEGORIES:home', 'X-APPLE-SORT-ORDER:42',
      'DESCRIPTION:Reminder', 'TRIGGER:-PT15M', 'LAST-MODIFIED:20200101T000000Z',
      'DUE;TZID=Europe/Rome:20261120T183000', // same day: original time kept
    ]) {
      expect(out, contains(keep));
    }
    expect(out, contains('SUMMARY:Buy bread'));
    expect(out, isNot(contains('Buy milk')));
    expect(out, contains('STATUS:COMPLETED'));
    expect(out, contains('COMPLETED:20261119T100000Z'));
    expect('SUMMARY:'.allMatches(out).length, 1);
    final back = itemFromIcs(out, 'p')!;
    expect(back.checked, true);
    expect(back.content, 'Buy bread');
  });

  test('new task round-trips, long lines fold', () {
    final i = Item(id: 'n1', content: 'x' * 200, projectId: 'p', priority: 4, due: DateTime(2026, 12, 1));
    final out = itemToIcs(i);
    expect(out, contains('DUE;VALUE=DATE:20261201'));
    expect(out, contains('PRIORITY:1'));
    expect(out.split('\r\n').every((l) => l.length <= 75), true);
    final back = itemFromIcs(out, 'p')!;
    expect(back.content, 'x' * 200);
    expect(back.priority, 4);
    expect(back.due, DateTime(2026, 12, 1));
  });
}
