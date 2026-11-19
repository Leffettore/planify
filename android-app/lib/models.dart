// Subset of Planify's data model (core/Objects/Item.vala, Project.vala).
// Priority follows Planify/Todoist: 4 = P1 (highest) ... 1 = none.

class Project {
  final String id;
  String name;
  String color;
  final bool inbox;

  Project({required this.id, required this.name, this.color = 'blue', this.inbox = false});

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'color': color, 'inbox_project': inbox ? 1 : 0};

  factory Project.fromMap(Map<String, Object?> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        color: (m['color'] as String?) ?? 'blue',
        inbox: m['inbox_project'] == 1,
      );
}

class Item {
  final String id;
  String content;
  String description;
  DateTime? due; // date only
  String projectId;
  int priority;
  bool checked;
  final DateTime addedAt;
  DateTime? completedAt;

  Item({
    required this.id,
    required this.content,
    this.description = '',
    this.due,
    required this.projectId,
    this.priority = 1,
    this.checked = false,
    DateTime? addedAt,
    this.completedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id,
        'content': content,
        'description': description,
        'due': due?.toIso8601String().substring(0, 10),
        'project_id': projectId,
        'priority': priority,
        'checked': checked ? 1 : 0,
        'added_at': addedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        content: m['content'] as String,
        description: (m['description'] as String?) ?? '',
        due: m['due'] == null ? null : DateTime.parse(m['due'] as String),
        projectId: m['project_id'] as String,
        priority: (m['priority'] as int?) ?? 1,
        checked: m['checked'] == 1,
        addedAt: DateTime.parse(m['added_at'] as String),
        completedAt: m['completed_at'] == null ? null : DateTime.parse(m['completed_at'] as String),
      );
}

/// What the task list is showing: Today, Scheduled, or one project.
sealed class TaskView {
  const TaskView();
}

class TodayView extends TaskView {
  const TodayView();
}

class ScheduledView extends TaskView {
  const ScheduledView();
}

class CompletedView extends TaskView {
  const CompletedView();
}

class ProjectView extends TaskView {
  final String projectId;
  const ProjectView(this.projectId);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Items for [view], open tasks only unless [showCompleted]. Today includes overdue.
List<Item> itemsFor(TaskView view, List<Item> all, DateTime now, {bool showCompleted = false}) {
  final today = dateOnly(now);
  if (view is CompletedView) {
    return all.where((i) => i.checked).toList()
      ..sort((a, b) => (b.completedAt ?? b.addedAt).compareTo(a.completedAt ?? a.addedAt));
  }
  final out = all.where((i) {
    if (i.checked && !showCompleted) return false;
    return switch (view) {
      TodayView() => i.due != null && !i.due!.isAfter(today),
      ScheduledView() => i.due != null && i.due!.isAfter(today),
      ProjectView(:final projectId) => i.projectId == projectId,
      CompletedView() => false,
    };
  }).toList();
  out.sort((a, b) {
    if (a.checked != b.checked) return a.checked ? 1 : -1;
    final ad = a.due, bd = b.due;
    if (ad != bd) {
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }
    if (a.priority != b.priority) return b.priority.compareTo(a.priority);
    return a.addedAt.compareTo(b.addedAt);
  });
  return out;
}

/// Section headers like Planify's: Today splits Overdue/Today, Scheduled groups by
/// day, Completed by completion day. Group key: 'overdue', or a day; null = no header.
List<(Object?, List<Item>)> groupItems(TaskView view, List<Item> sorted, DateTime now) {
  final today = dateOnly(now);
  Object? key(Item i) => switch (view) {
        TodayView() => i.due!.isBefore(today) ? 'overdue' : today,
        ScheduledView() => i.due,
        CompletedView() => dateOnly(i.completedAt ?? i.addedAt),
        ProjectView() => null,
      };
  final groups = <(Object?, List<Item>)>[];
  for (final i in sorted) {
    final k = key(i);
    if (groups.isNotEmpty && groups.last.$1 == k) {
      groups.last.$2.add(i);
    } else {
      groups.add((k, [i]));
    }
  }
  return groups;
}
