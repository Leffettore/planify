import 'package:flutter_test/flutter_test.dart';
import 'package:planify/models.dart';

void main() {
  final now = DateTime(2026, 11, 19, 15, 30);
  Item item(String id, {DateTime? due, String project = 'p', int priority = 1, bool checked = false}) =>
      Item(id: id, content: id, due: due, projectId: project, priority: priority, checked: checked,
          addedAt: DateTime(2026, 1, 1));

  final all = [
    item('overdue', due: DateTime(2026, 11, 18)),
    item('today-p1', due: DateTime(2026, 11, 19), priority: 4),
    item('today', due: DateTime(2026, 11, 19)),
    item('tomorrow', due: DateTime(2026, 11, 20), project: 'q'),
    item('nodate'),
    item('done', due: DateTime(2026, 11, 19), checked: true),
  ];
  ids(List<Item> l) => l.map((i) => i.id).toList();

  test('today includes overdue, sorted by date then priority, hides completed', () {
    expect(ids(itemsFor(const TodayView(), all, now)), ['overdue', 'today-p1', 'today']);
  });

  test('completed shown last when requested', () {
    expect(ids(itemsFor(const TodayView(), all, now, showCompleted: true)).last, 'done');
  });

  test('scheduled is future only', () {
    expect(ids(itemsFor(const ScheduledView(), all, now)), ['tomorrow']);
  });

  test('project view filters by project, undated last', () {
    expect(ids(itemsFor(const ProjectView('p'), all, now)), ['overdue', 'today-p1', 'today', 'nodate']);
  });

  test('completed view lists checked items, newest first', () {
    final a = item('a', checked: true)..completedAt = DateTime(2026, 11, 1);
    final b = item('b', checked: true)..completedAt = DateTime(2026, 11, 5);
    expect(ids(itemsFor(const CompletedView(), [...all, a, b], now)), ['b', 'a', 'done']);
  });

  test('today groups into overdue then today', () {
    final g = groupItems(const TodayView(), itemsFor(const TodayView(), all, now), now);
    expect(g.map((e) => '${e.$1}: ${ids(e.$2)}').toList(), [
      'overdue: [overdue]',
      '${DateTime(2026, 11, 19)}: [today-p1, today]',
    ]);
  });

  test('project view has a single headerless group', () {
    final g = groupItems(const ProjectView('p'), itemsFor(const ProjectView('p'), all, now), now);
    expect([g.length, g.single.$1], [1, null]);
  });

  test('item round-trips through a db map', () {
    final i = item('x', due: DateTime(2026, 2, 3), priority: 3, checked: true);
    final back = Item.fromMap(i.toMap());
    expect([back.due, back.priority, back.checked, back.projectId], [DateTime(2026, 2, 3), 3, true, 'p']);
  });
}
