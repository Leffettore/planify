// Two-way CalDAV sync: projects = VTODO calendars, items = VTODOs. Same layout as
// Planify desktop's CalDAV account, so both see the same data.
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'db.dart';
import 'ical.dart';
import 'models.dart';

const _dav = 'DAV:', _cal = 'urn:ietf:params:xml:ns:caldav', _ical = 'http://apple.com/ns/ical/';

String colorHex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class CalDav {
  final Uri base;
  final String _auth;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  CalDav(String url, String user, String password)
    : base = Uri.parse(url.endsWith('/') ? url : '$url/'),
      _auth = 'Basic ${base64.encode(utf8.encode('$user:$password'))}';

  Future<(int, String)> _send(
    String method,
    String path, {
    String? body,
    String type = 'application/xml',
    Map<String, String> headers = const {},
  }) async {
    final req = await _http.openUrl(method, base.resolve(path));
    req.headers.set('Authorization', _auth);
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.parse('$type; charset=utf-8');
      final bytes = utf8.encode(body);
      req.contentLength = bytes.length; // Radicale ignores chunked request bodies
      req.add(bytes);
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode == 401) throw const HttpException('Wrong username or password');
    return (res.statusCode, text);
  }

  Future<void> _expect(String method, String path, Set<int> ok, {String? body, String type = 'application/xml'}) async {
    final (code, _) = await _send(method, path, body: body, type: type);
    if (!ok.contains(code)) throw HttpException('$method $path: HTTP $code');
  }

  /// `response` elements of a 207 Multi-Status.
  Future<Iterable<XmlElement>> _multi(String method, String path, String body, {String depth = '0'}) async {
    final (code, text) = await _send(method, path, body: body, headers: {'Depth': depth});
    if (code != 207) throw HttpException('$method $path: HTTP $code');
    return XmlDocument.parse(text).findAllElements('response', namespaceUri: _dav);
  }

  static String? _text(XmlElement e, String name, String ns) =>
      e.findAllElements(name, namespaceUri: ns).firstOrNull?.innerText.trim();

  Future<String> _hrefProp(String path, String prop, String ns) async {
    final r = await _multi(
      'PROPFIND',
      path,
      '<d:propfind xmlns:d="DAV:" xmlns:c="$_cal"><d:prop><x:$prop xmlns:x="$ns"/></d:prop></d:propfind>',
    );
    final href = r
        .map((e) => e.findAllElements(prop, namespaceUri: ns).firstOrNull)
        .map((p) => p == null ? null : _text(p, 'href', _dav))
        .nonNulls
        .firstOrNull;
    if (href == null) throw HttpException('Server has no $prop');
    return href;
  }

  Future<String> calendarHome() async =>
      _hrefProp(await _hrefProp('', 'current-user-principal', _dav), 'calendar-home-set', _cal);

  /// (href, name, color hex) of every task calendar in [home].
  Future<List<(String, String, String?)>> calendars(String home) async {
    final r = await _multi(
      'PROPFIND',
      home,
      '<d:propfind xmlns:d="DAV:" xmlns:c="$_cal" xmlns:i="$_ical"><d:prop><d:resourcetype/><d:displayname/>'
          '<i:calendar-color/><c:supported-calendar-component-set/></d:prop></d:propfind>',
      depth: '1',
    );
    return [
      for (final e in r)
        if (e.findAllElements('calendar', namespaceUri: _cal).isNotEmpty &&
            e.findAllElements('comp', namespaceUri: _cal).any((c) => c.getAttribute('name') == 'VTODO'))
          (_text(e, 'href', _dav)!, _text(e, 'displayname', _dav) ?? '', _text(e, 'calendar-color', _ical)),
    ];
  }

  /// (href, iCalendar) of every task in [calendar].
  Future<List<(String, String)>> todos(String calendar) async {
    final r = await _multi(
      'REPORT',
      calendar,
      '<c:calendar-query xmlns:d="DAV:" xmlns:c="$_cal"><d:prop><c:calendar-data/></d:prop>'
          '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VTODO"/></c:comp-filter></c:filter></c:calendar-query>',
      depth: '1',
    );
    return [
      for (final e in r)
        if (_text(e, 'calendar-data', _cal) case final data? when data.isNotEmpty) (_text(e, 'href', _dav)!, data),
    ];
  }

  String _props(Project p, int argb) =>
      '<d:displayname>${XmlText(p.name)}</d:displayname>'
      '<i:calendar-color>${colorHex(argb)}</i:calendar-color>';

  /// Creates the calendar at [href], or updates it if it already exists.
  Future<void> putCalendar(String href, Project p, int argb, {required bool create}) async {
    if (create) {
      final (code, _) = await _send(
        'MKCOL',
        href,
        body:
            '<d:mkcol xmlns:d="DAV:" xmlns:c="$_cal" xmlns:i="$_ical"><d:set><d:prop>'
            '<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>${_props(p, argb)}'
            '<c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>'
            '</d:prop></d:set></d:mkcol>',
      );
      if (code == 201) return;
      if (code != 405) throw HttpException('MKCOL $href: HTTP $code'); // 405 = exists, update it below
    }
    await _expect(
      'PROPPATCH',
      href,
      {207},
      body:
          '<d:propertyupdate xmlns:d="DAV:" xmlns:i="$_ical"><d:set><d:prop>${_props(p, argb)}</d:prop></d:set></d:propertyupdate>',
    );
  }

  Future<void> put(String href, String ics) => _expect('PUT', href, {200, 201, 204}, body: ics, type: 'text/calendar');

  Future<void> delete(String href) => _expect('DELETE', href, {200, 204, 404});

  void close() => _http.close(force: true);
}

/// Pushes local changes, then pulls everything. Returns an error message or null.
/// [colors] maps Planify color names to ARGB.
Future<String?> syncOnce(Db db, Map<String, int> colors) async {
  final url = await db.setting('url'), user = await db.setting('user'), pw = await db.setting('password');
  if (url == null || url.isEmpty) return null;
  final dav = CalDav(url, user ?? '', pw ?? '');
  try {
    final home = await dav.calendarHome();

    for (final href in await db.tombstones()) {
      await dav.delete(href);
      await db.dropTombstone(href);
    }

    for (final (p, dirty) in await db.dirtyProjects()) {
      final href = p.href ?? '$home${p.inbox ? 'inbox' : p.id}/';
      await dav.putCalendar(href, p, colors[p.color] ?? colors['blue']!, create: p.href == null);
      await db.markPushed('Projects', p.id, dirty, {'href': href});
    }

    final projectHref = {for (final p in await db.projects()) p.id: p.href};
    for (final (i, dirty) in await db.dirtyItems()) {
      final cal = projectHref[i.projectId];
      if (cal == null) continue; // its project failed to push; retried next sync
      final href = i.href ?? '$cal${Uri.encodeComponent(i.id)}.ics';
      final ics = itemToIcs(i);
      await dav.put(href, ics);
      await db.markPushed('Items', i.id, dirty, {'href': href, 'ical': ics});
    }

    final local = {for (final p in await db.projects()) p.href: p};
    final projects = <Project>[], items = <Item>[];
    for (final (href, name, hex) in await dav.calendars(home)) {
      final hex6 = hex == null || hex.length < 7 ? null : hex.substring(0, 7).toUpperCase();
      final color =
          colors.entries.where((e) => colorHex(e.value) == hex6).firstOrNull?.key ?? local[href]?.color ?? 'blue';
      final id = local[href]?.id ?? href.split('/').where((s) => s.isNotEmpty).last;
      projects.add(Project(id: id, name: name, color: color, inbox: local[href]?.inbox ?? false, href: href));
      for (final (ihref, ics) in await dav.todos(href)) {
        final item = itemFromIcs(ics, id);
        if (item != null) items.add(item..href = ihref);
      }
    }
    await db.applyPull(projects, items);
    return null;
  } on SocketException catch (e) {
    return 'Server unreachable (is Tailscale on?): ${e.message}';
  } catch (e) {
    return '$e';
  } finally {
    dav.close();
  }
}
