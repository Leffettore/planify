// Minimal VTODO <-> Item mapping, compatible with Planify desktop's CalDAV
// (core/Objects/Item.vala patch_from_vtodo / to_vtodo).
import 'models.dart';

/// Properties this app owns. Everything else in a task's original iCalendar
/// (RRULE, RELATED-TO, CATEGORIES, VALARM, X-APPLE-SORT-ORDER...) is kept on write.
const _managed = {
  'SUMMARY',
  'DESCRIPTION',
  'DUE',
  'PRIORITY',
  'STATUS',
  'COMPLETED',
  'PERCENT-COMPLETE',
  'DTSTAMP',
  'LAST-MODIFIED',
};

List<String> _unfold(String ics) =>
    ics.replaceAll(RegExp(r'\r?\n[ \t]'), '').split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).toList();

String _name(String line) => line.split(RegExp('[;:]')).first.toUpperCase();

String _value(String line) {
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '"') quoted = !quoted;
    if (line[i] == ':' && !quoted) return line.substring(i + 1);
  }
  return '';
}

String _unescape(String v) => v.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => switch (m[1]) {
    'n' || 'N' => '\n',
    final c => c!,
  },
);

String _escape(String v) =>
    v.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

String _fold(String line) {
  final runes = line.runes.toList();
  if (runes.length <= 74) return line;
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i += 72) {
    if (i > 0) out.write('\r\n ');
    out.write(String.fromCharCodes(runes.sublist(i, i + 72 > runes.length ? runes.length : i + 72)));
  }
  return out.toString();
}

/// 20261119, 20261119T100000 or 20261119T100000Z.
DateTime? _parseTime(String v) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?').firstMatch(v);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m[i] ?? '0')];
  return m[7] != null
      ? DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]).toLocal()
      : DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
}

String _utc(DateTime d) => '${d.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
String _date(DateTime d) => _utc(DateTime.utc(d.year, d.month, d.day)).substring(0, 8);

/// Pushes/pops BEGIN/END onto [stack]; true if [l] was one of them.
bool _track(List<String> stack, String l) {
  final u = l.toUpperCase();
  if (u.startsWith('BEGIN:')) stack.add(u.substring(6));
  if (u.startsWith('END:') && stack.isNotEmpty) stack.removeLast();
  return u.startsWith('BEGIN:') || u.startsWith('END:');
}

/// VTODO-level property lines of [ics] (not those of nested VALARMs).
Map<String, String> _props(String ics) {
  final out = <String, String>{};
  final stack = <String>[];
  for (final l in _unfold(ics)) {
    if (!_track(stack, l) && stack.lastOrNull == 'VTODO') out.putIfAbsent(_name(l), () => l);
  }
  return out;
}

/// Parses a task; null if [ics] has no VTODO.
Item? itemFromIcs(String ics, String projectId) {
  final p = _props(ics);
  final uid = p['UID'];
  if (uid == null) return null;
  String? v(String k) => p[k] == null ? null : _value(p[k]!);
  final prio = int.tryParse(v('PRIORITY') ?? '') ?? 0;
  final done = v('STATUS') == 'COMPLETED' || v('PERCENT-COMPLETE') == '100';
  final due = _parseTime(v('DUE') ?? '');
  return Item(
    id: _unescape(_value(uid)),
    content: _unescape(v('SUMMARY') ?? ''),
    description: _unescape(v('DESCRIPTION') ?? ''),
    due: due == null ? null : dateOnly(due),
    projectId: projectId,
    priority: prio <= 0 || prio > 9
        ? 1
        : prio <= 4
        ? 4
        : prio == 5
        ? 3
        : 2,
    checked: done,
    addedAt: _parseTime(v('CREATED') ?? v('DTSTAMP') ?? ''),
    completedAt: done ? (_parseTime(v('COMPLETED') ?? '') ?? DateTime.now()) : null,
  )..ical = ics;
}

/// Serializes [i], patching its original iCalendar when it has one.
String itemToIcs(Item i, {DateTime? now}) {
  final stamp = _utc(now ?? DateTime.now());
  final orig = i.ical == null ? null : _props(i.ical!)['DUE'];
  final origDue = orig == null ? null : _parseTime(_value(orig));
  final props = [
    'SUMMARY:${_escape(i.content)}',
    if (i.description.isNotEmpty) 'DESCRIPTION:${_escape(i.description)}',
    // Keep the desktop's DUE (it may carry a time) if the day did not change.
    if (i.due != null) origDue != null && dateOnly(origDue) == i.due ? orig! : 'DUE;VALUE=DATE:${_date(i.due!)}',
    'PRIORITY:${const {4: 1, 3: 5, 2: 9}[i.priority] ?? 0}',
    'STATUS:${i.checked ? 'COMPLETED' : 'NEEDS-ACTION'}',
    if (i.checked) 'COMPLETED:${_utc(i.completedAt ?? DateTime.now())}',
    if (i.checked) 'PERCENT-COMPLETE:100',
    'DTSTAMP:$stamp',
    'LAST-MODIFIED:$stamp',
  ];
  final lines = i.ical == null
      ? [
          'BEGIN:VCALENDAR',
          'VERSION:2.0',
          'PRODID:-//Planify Android//EN',
          'BEGIN:VTODO',
          'UID:${i.id}',
          'CREATED:${_utc(i.addedAt)}',
          'END:VTODO',
          'END:VCALENDAR',
        ]
      : _unfold(i.ical!);
  final out = <String>[];
  final stack = <String>[];
  for (final l in lines) {
    final inTodo = stack.lastOrNull == 'VTODO';
    if (inTodo && l.toUpperCase() == 'END:VTODO') out.addAll(props);
    if (!_track(stack, l) && inTodo && _managed.contains(_name(l))) continue;
    out.add(l);
  }
  return '${out.map(_fold).join('\r\n')}\r\n';
}
