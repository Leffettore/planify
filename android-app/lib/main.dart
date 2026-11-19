import 'package:flutter/material.dart';

import 'db.dart';
import 'models.dart';

// Planify's project palette (core/Utils/Util.vala get_colors).
const projectColors = <String, Color>{
  'berry_red': Color(0xFFC42D78),
  'red': Color(0xFFE23D3D),
  'orange': Color(0xFFFF8A2A),
  'yellow': Color(0xFFF5C400),
  'olive_green': Color(0xFF9CAB3A),
  'lime_green': Color(0xFF70C741),
  'green': Color(0xFF27983A),
  'mint_green': Color(0xFF55CBB0),
  'teal': Color(0xFF1492B2),
  'sky_blue': Color(0xFF139EF7),
  'light_blue': Color(0xFF7FB9E8),
  'blue': Color(0xFF3C6DFF),
  'grape': Color(0xFF7B44E6),
  'violet': Color(0xFFA02ADB),
  'lavender': Color(0xFFD89AE8),
  'magenta': Color(0xFFD6458D),
  'salmon': Color(0xFFF77C70),
  'charcoal': Color(0xFF666666),
  'grey': Color(0xFFA0A0A0),
  'taupe': Color(0xFFB99780),
};

const accent = Color(0xFF3584E4);
const todayColor = Color(0xFF33D17A);
const todayChip = Color(0xFF16AF54);
const overdueColor = Color(0xFFFA1955);
const destructive = Color(0xFFE01B24);

/// Planify's surface colors (Util.vala update_theme) and filter colors (core/Objects/Filters).
class Pal {
  final bool dark;
  const Pal(this.dark);
  static Pal of(BuildContext c) => Pal(Theme.of(c).brightness == Brightness.dark);

  Color get window => dark ? const Color(0xFF0C0D12) : const Color(0xFFF9F9F9);
  Color get sidebar => dark ? const Color(0xFF14151A) : const Color(0xFFF3F4F6);
  Color get popover => dark ? const Color(0xFF16171D) : Colors.white;
  Color get border => dark ? const Color(0xFF2D2F35) : const Color(0xFFDCDFE3);
  Color get upcomingBg => dark ? const Color(0xFF2A2D34) : const Color(0xFFF0F1F3);
  Color get upcomingFg => dark ? const Color(0xFFE6E9EF) : const Color(0xFF2D2E32);
  Color get dim => dark ? Colors.white54 : Colors.black45;
  Color get inbox => dark ? const Color(0xFF99C1F1) : accent;
  Color get scheduled => dark ? const Color(0xFFDC8ADD) : const Color(0xFF9141AC);
  Color get completed => dark ? const Color(0xFFFFBE6F) : const Color(0xFFFF7800);

  // Item priority 4 = P1 ... 1 = none (stylesheet.css .priority-N-color).
  Color priority(int p) => switch (p) {
        4 => const Color(0xFFFF7066),
        3 => const Color(0xFFFF9A14),
        2 => const Color(0xFF5297FF),
        _ => dark ? Colors.white38 : Colors.black38,
      };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await Db.open());
  await state.load();
  runApp(PlanifyApp(state: state));
}

class AppState extends ChangeNotifier {
  final Db db;
  List<Project> projects = [];
  List<Item> items = [];
  AppState(this.db);

  Project get inbox => projects.firstWhere((p) => p.inbox);
  Project? project(String id) => projects.where((p) => p.id == id).firstOrNull;

  Future<void> load() async {
    projects = await db.projects();
    items = await db.items();
    notifyListeners();
  }

  int count(TaskView v) => itemsFor(v, items, DateTime.now()).length;

  bool get hasOverdue {
    final today = dateOnly(DateTime.now());
    return items.any((i) => !i.checked && i.due != null && i.due!.isBefore(today));
  }

  Future<void> toggle(Item i) async {
    i.checked = !i.checked;
    i.completedAt = i.checked ? DateTime.now() : null;
    await db.saveItem(i);
    await load();
  }

  Future<void> saveItem(Item i) async {
    await db.saveItem(i);
    await load();
  }

  Future<void> deleteItem(Item i) async {
    await db.deleteItem(i.id);
    await load();
  }

  Future<void> saveProject(Project p) async {
    await db.saveProject(p);
    await load();
  }

  Future<void> deleteProject(Project p) async {
    await db.deleteProject(p.id);
    await load();
  }
}

class PlanifyApp extends StatelessWidget {
  final AppState state;
  const PlanifyApp({super.key, required this.state});

  ThemeData _theme(Brightness b) {
    final pal = Pal(b == Brightness.dark);
    final base = ThemeData(
      brightness: b,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: b, primary: accent, surface: pal.window),
      scaffoldBackgroundColor: pal.window,
      dividerColor: pal.border,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: pal.window,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 4,
        titleTextStyle: base.textTheme.titleMedium!.copyWith(fontFamily: 'Inter', fontWeight: FontWeight.w700),
      ),
      dividerTheme: DividerThemeData(color: pal.border, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: pal.popover, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: pal.popover, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: pal.popover, surfaceTintColor: Colors.transparent),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
        elevation: 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Planify',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: SidebarPage(state: state),
      );
}

// ---------------------------------------------------------------------------
// Sidebar: on a phone it is the home page, like Planify's adaptive layout.

class SidebarPage extends StatelessWidget {
  final AppState state;
  const SidebarPage({super.key, required this.state});

  void _open(BuildContext context, TaskView v) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => TaskListPage(state: state, view: v)));

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.sidebar,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final projects = state.projects.where((p) => !p.inbox).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                  children: [
                    FilterTile(
                        icon: Icons.inbox_outlined,
                        label: 'Inbox',
                        color: pal.inbox,
                        count: state.count(ProjectView(state.inbox.id)),
                        onTap: () => _open(context, ProjectView(state.inbox.id))),
                    FilterTile(
                        icon: Icons.star_border_rounded,
                        label: 'Today',
                        color: todayColor,
                        count: state.count(const TodayView()),
                        dot: state.hasOverdue,
                        onTap: () => _open(context, const TodayView())),
                    FilterTile(
                        icon: Icons.calendar_month_outlined,
                        label: 'Scheduled',
                        color: pal.scheduled,
                        count: state.count(const ScheduledView()),
                        onTap: () => _open(context, const ScheduledView())),
                    FilterTile(
                        icon: Icons.task_alt_rounded,
                        label: 'Completed',
                        color: pal.completed,
                        count: state.count(const CompletedView()),
                        onTap: () => _open(context, const CompletedView())),
                  ],
                ),
                const SizedBox(height: 16),
                SectionHeader(
                  title: 'On This Device',
                  trailing: IconButton(
                    tooltip: 'Add project',
                    icon: const Icon(Icons.add, size: 22),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final p = await editProject(context, state);
                      if (p != null && context.mounted) _open(context, ProjectView(p.id));
                    },
                  ),
                ),
                if (projects.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('No projects yet', style: TextStyle(color: pal.dim)),
                  ),
                for (final p in projects)
                  InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => _open(context, ProjectView(p.id)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                      child: Row(children: [
                        ProjectDot(color: projectColors[p.color] ?? accent),
                        const SizedBox(width: 12),
                        Expanded(child: Text(p.name, style: const TextStyle(fontSize: 15))),
                        Text(_countLabel(state.count(ProjectView(p.id))),
                            style: TextStyle(fontSize: 12, color: pal.dim)),
                        const SizedBox(width: 8),
                      ]),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _countLabel(int n) => n == 0 ? '' : '$n';

class FilterTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int count;
  final bool dot;
  final VoidCallback onTap;

  const FilterTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.count,
    required this.onTap,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final bold = TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15);
    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: color, size: 18),
                const Spacer(),
                Text(_countLabel(count), style: bold),
              ]),
              const Spacer(),
              Row(children: [
                Text(label, style: bold),
                const Spacer(),
                if (dot)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFFE5534B), shape: BoxShape.circle),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Planify's project icon: a colored ring around a filled dot.
class ProjectDot extends StatelessWidget {
  final Color color;
  final double size;
  const ProjectDot({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
        child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              ?trailing,
            ]),
          ),
          const Divider(),
          const SizedBox(height: 4),
        ],
      );
}

// ---------------------------------------------------------------------------
// Task list

class TaskListPage extends StatefulWidget {
  final AppState state;
  final TaskView view;
  const TaskListPage({super.key, required this.state, required this.view});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  bool showCompleted = false;
  AppState get state => widget.state;
  TaskView get view => widget.view;

  Future<void> _editItem([Item? item]) async {
    final result = await showModalBottomSheet<_ItemEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ItemEditor(
        item: item,
        projects: state.projects,
        defaultProjectId: switch (view) { ProjectView(:final projectId) => projectId, _ => state.inbox.id },
        defaultDue: view is TodayView ? dateOnly(DateTime.now()) : null,
      ),
    );
    if (result == null) return;
    if (result.delete) {
      await state.deleteItem(item!);
    } else {
      await state.saveItem(result.item!);
    }
  }

  Future<void> _deleteProject(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('All of its tasks will be deleted too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: destructive),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    await state.deleteProject(p);
  }

  String _header(Object? key, MaterialLocalizations loc) {
    if (key == 'overdue') return 'Overdue';
    final d = key as DateTime;
    return switch (daysBetween(dateOnly(DateTime.now()), d)) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => loc.formatFullDate(d),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final loc = MaterialLocalizations.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final project = switch (view) { ProjectView(:final projectId) => state.project(projectId), _ => null };
        // Project was deleted while this page was open.
        if (view is ProjectView && project == null) return const Scaffold();

        final now = DateTime.now();
        final groups = groupItems(view, itemsFor(view, state.items, now, showCompleted: showCompleted), now);
        final (title, icon, iconColor) = switch (view) {
          TodayView() => ('Today', Icons.star_border_rounded, todayColor),
          ScheduledView() => ('Scheduled', Icons.calendar_month_outlined, pal.scheduled),
          CompletedView() => ('Completed', Icons.task_alt_rounded, pal.completed),
          ProjectView() when project!.inbox => ('Inbox', Icons.inbox_outlined, pal.inbox),
          ProjectView() => (project!.name, null, null),
        };

        return Scaffold(
          appBar: AppBar(
            title: Row(children: [
              if (icon != null)
                Icon(icon, color: iconColor, size: 20)
              else
                ProjectDot(color: projectColors[project!.color] ?? accent),
              const SizedBox(width: 10),
              Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
              if (view is TodayView) ...[
                const SizedBox(width: 8),
                Text(loc.formatShortMonthDay(now),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.dim)),
              ],
            ]),
            actions: [
              if (view is! CompletedView)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) => switch (v) {
                    'completed' => setState(() => showCompleted = !showCompleted),
                    'edit' => editProject(context, state, project),
                    _ => _deleteProject(project!),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'completed',
                      child: Text(showCompleted ? 'Hide completed tasks' : 'Show completed tasks'),
                    ),
                    if (project != null && !project.inbox) ...[
                      const PopupMenuItem(value: 'edit', child: Text('Edit project')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete project', style: TextStyle(color: destructive)),
                      ),
                    ],
                  ],
                ),
            ],
          ),
          body: groups.isEmpty
              ? EmptyState(view: view)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  children: [
                    for (final (key, items) in groups) ...[
                      if (key != null) ...[
                        const SizedBox(height: 8),
                        SectionHeader(title: _header(key, loc)),
                      ],
                      for (final i in items)
                        ItemRow(
                          item: i,
                          projectName: view is ProjectView ? null : state.project(i.projectId)?.name,
                          // Scheduled/Completed headers already say the day.
                          showDue: view is ProjectView || view is TodayView,
                          onToggle: () => state.toggle(i),
                          onTap: () => _editItem(i),
                        ),
                    ],
                  ],
                ),
          floatingActionButton: view is CompletedView
              ? null
              : FloatingActionButton(tooltip: 'Add task', onPressed: _editItem, child: const Icon(Icons.add)),
        );
      },
    );
  }
}

// UTC so a DST shift (23h day) does not round to the wrong day.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

class EmptyState extends StatelessWidget {
  final TaskView view;
  const EmptyState({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final (icon, text) = switch (view) {
      TodayView() => (Icons.star_border_rounded, 'Nothing for today'),
      ScheduledView() => (Icons.calendar_month_outlined, 'Nothing scheduled'),
      CompletedView() => (Icons.task_alt_rounded, 'No completed tasks yet'),
      ProjectView() => (Icons.checklist_rounded, 'Press + to add a task'),
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: pal.dim),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(color: pal.dim)),
      ]),
    );
  }
}

class ItemRow extends StatelessWidget {
  final Item item;
  final String? projectName;
  final bool showDue;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const ItemRow({
    super.key,
    required this.item,
    required this.projectName,
    required this.showDue,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final name = projectName;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(children: [
          PlanifyCheck(checked: item.checked, color: pal.priority(item.priority), onTap: onToggle),
          if (showDue && item.due != null && !item.checked) ...[
            DueChip(due: item.due!),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                item.content,
                style: item.checked
                    ? TextStyle(fontSize: 15, color: pal.dim, decoration: TextDecoration.lineThrough)
                    : const TextStyle(fontSize: 15),
              ),
            ),
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(width: 6),
            Icon(Icons.notes_rounded, size: 16, color: pal.dim),
          ],
          if (name != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.dim)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Planify's rounded-square checkbox: priority-colored border, orange when done.
class PlanifyCheck extends StatelessWidget {
  final bool checked;
  final Color color;
  final VoidCallback? onTap;
  const PlanifyCheck({super.key, required this.checked, required this.color, this.onTap});

  static const _done = Color(0xFFFF7800);

  @override
  Widget build(BuildContext context) => Semantics(
        checked: checked,
        button: onTap != null,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: SizedBox(
            width: 36,
            height: 40,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  color: checked ? _done : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: checked ? _done : color, width: 2),
                ),
                child: checked ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
              ),
            ),
          ),
        ),
      );
}

/// Date pill: green for today, red when overdue, grey otherwise.
class DueChip extends StatelessWidget {
  final DateTime due;
  const DueChip({super.key, required this.due});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final diff = daysBetween(dateOnly(DateTime.now()), due);
    final (fg, bg) = diff == 0
        ? (todayChip, todayChip.withValues(alpha: 0.15))
        : diff < 0
            ? (overdueColor, overdueColor.withValues(alpha: 0.125))
            : (pal.upcomingFg, pal.upcomingBg);
    final label = switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => MaterialLocalizations.of(context).formatShortMonthDay(due),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}

// ---------------------------------------------------------------------------
// Editors

class _ItemEdit {
  final Item? item;
  final bool delete;
  _ItemEdit.save(this.item) : delete = false;
  _ItemEdit.delete()
      : item = null,
        delete = true;
}

class ItemEditor extends StatefulWidget {
  final Item? item;
  final List<Project> projects;
  final String defaultProjectId;
  final DateTime? defaultDue;

  const ItemEditor({
    super.key,
    this.item,
    required this.projects,
    required this.defaultProjectId,
    this.defaultDue,
  });

  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  late final content = TextEditingController(text: widget.item?.content);
  late final description = TextEditingController(text: widget.item?.description);
  late DateTime? due = widget.item?.due ?? (widget.item == null ? widget.defaultDue : null);
  late int priority = widget.item?.priority ?? 1;
  late String projectId = widget.item?.projectId ?? widget.defaultProjectId;

  @override
  void dispose() {
    content.dispose();
    description.dispose();
    super.dispose();
  }

  void _save() {
    final text = content.text.trim();
    if (text.isEmpty) return;
    final i = widget.item ?? Item(id: newId(), content: text, projectId: projectId);
    i
      ..content = text
      ..description = description.text.trim()
      ..due = due
      ..priority = priority
      ..projectId = projectId;
    Navigator.pop(context, _ItemEdit.save(i));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: due ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) setState(() => due = d);
  }

  Widget _projectIcon(Project p, Pal pal, double size) => p.inbox
      ? Icon(Icons.inbox_outlined, size: size + 2, color: pal.inbox)
      : ProjectDot(color: projectColors[p.color] ?? accent, size: size);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final project = widget.projects.firstWhere((p) => p.id == projectId);
    return Padding(
      // Keyboard height, or the gesture-nav bar when the keyboard is closed.
      padding: EdgeInsets.fromLTRB(16, 0, 16,
          12 + [MediaQuery.viewInsetsOf(context).bottom, MediaQuery.viewPaddingOf(context).bottom].reduce((a, b) => a > b ? a : b)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            PlanifyCheck(checked: false, color: pal.priority(priority)),
            Expanded(
              child: TextField(
                controller: content,
                autofocus: widget.item == null,
                decoration: const InputDecoration(hintText: 'To-do name', border: InputBorder.none),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: TextField(
              controller: description,
              decoration: InputDecoration(
                hintText: 'Add a description…',
                border: InputBorder.none,
                hintStyle: TextStyle(color: pal.dim),
              ),
              style: const TextStyle(fontSize: 14),
              maxLines: null,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ToolButton(
              icon: Icons.calendar_today_outlined,
              iconColor: due == null ? null : todayChip,
              label: due == null ? 'Schedule' : MaterialLocalizations.of(context).formatMediumDate(due!),
              onTap: _pickDate,
              onClear: due == null ? null : () => setState(() => due = null),
            ),
            PopupMenuButton<int>(
              tooltip: 'Priority',
              initialValue: priority,
              onSelected: (v) => setState(() => priority = v),
              itemBuilder: (_) => [
                for (final p in [4, 3, 2, 1])
                  PopupMenuItem(
                    value: p,
                    child: Row(children: [
                      Icon(p == 1 ? Icons.outlined_flag : Icons.flag, color: pal.priority(p), size: 20),
                      const SizedBox(width: 10),
                      Text(p == 1 ? 'None' : 'Priority ${5 - p}'),
                    ]),
                  ),
              ],
              child: ToolButton(
                icon: priority == 1 ? Icons.outlined_flag : Icons.flag,
                iconColor: priority == 1 ? null : pal.priority(priority),
                label: priority == 1 ? 'Priority' : 'P${5 - priority}',
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Project',
              initialValue: projectId,
              onSelected: (v) => setState(() => projectId = v),
              itemBuilder: (_) => [
                for (final p in widget.projects)
                  PopupMenuItem(
                    value: p.id,
                    child: Row(children: [_projectIcon(p, pal, 16), const SizedBox(width: 10), Text(p.name)]),
                  ),
              ],
              child: ToolButton(leading: _projectIcon(project, pal, 14), label: project.name),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(children: [
            if (widget.item != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline, color: destructive),
                onPressed: () => Navigator.pop(context, _ItemEdit.delete()),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
              onPressed: _save,
              child: Text(widget.item == null ? 'Add To-Do' : 'Save'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Flat bordered button like the ones under Planify's quick-add entry.
class ToolButton extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final Color? iconColor;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const ToolButton({super.key, this.icon, this.leading, this.iconColor, required this.label, this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(border: Border.all(color: pal.border), borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        leading ?? Icon(icon, size: 18, color: iconColor ?? pal.dim),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        if (onClear != null) ...[
          const SizedBox(width: 4),
          GestureDetector(onTap: onClear, child: Icon(Icons.close, size: 16, color: pal.dim)),
        ],
      ]),
    );
    return onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(9), onTap: onTap, child: body);
  }
}

Future<Project?> editProject(BuildContext context, AppState state, [Project? project]) async {
  final p = await showDialog<Project>(context: context, builder: (_) => ProjectDialog(project: project));
  if (p != null) await state.saveProject(p);
  return p;
}

class ProjectDialog extends StatefulWidget {
  final Project? project;
  const ProjectDialog({super.key, this.project});

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  late final name = TextEditingController(text: widget.project?.name);
  // Old projects may carry a color name that is not in the palette.
  late String color = projectColors.containsKey(widget.project?.color) ? widget.project!.color : 'blue';

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _save() {
    final text = name.text.trim();
    if (text.isEmpty) return;
    final p = widget.project ?? Project(id: newId(), name: text);
    p
      ..name = text
      ..color = color;
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.project == null ? 'New Project' : 'Edit Project',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Project name',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(14),
                  child: ProjectDot(color: projectColors[color]!, size: 16),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in projectColors.entries)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => color = e.key),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: e.value,
                      child: color == e.key ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
