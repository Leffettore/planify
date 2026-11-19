import 'package:flutter/material.dart';

import 'db.dart';
import 'models.dart';

// A few of Planify's project colors (core/Utils/Util.vala).
const projectColors = <String, Color>{
  'blue': Color(0xFF4073FF),
  'red': Color(0xFFDB4035),
  'orange': Color(0xFFFF9933),
  'yellow': Color(0xFFFAD000),
  'green': Color(0xFF299438),
  'teal': Color(0xFF158FAD),
  'violet': Color(0xFFAF38EB),
  'grey': Color(0xFFB8B8B8),
};

const priorityColors = {4: Color(0xFFFF7066), 3: Color(0xFFFF9A14), 2: Color(0xFF5297FF), 1: Colors.grey};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PlanifyApp(db: await Db.open()));
}

class PlanifyApp extends StatelessWidget {
  final Db db;
  const PlanifyApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) =>
        ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: projectColors['blue']!, brightness: b));
    return MaterialApp(
      title: 'Planify',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomePage(db: db),
    );
  }
}

class HomePage extends StatefulWidget {
  final Db db;
  const HomePage({super.key, required this.db});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Project> projects = [];
  List<Item> items = [];
  TaskView view = const TodayView();
  bool showCompleted = false;

  Db get db => widget.db;
  Project get inbox => projects.firstWhere((p) => p.inbox);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final p = await db.projects();
    final i = await db.items();
    setState(() {
      projects = p;
      items = i;
      if (view case ProjectView(:final projectId) when !p.any((x) => x.id == projectId)) {
        view = const TodayView();
      }
    });
  }

  String get title => switch (view) {
        TodayView() => 'Today',
        ScheduledView() => 'Scheduled',
        ProjectView(:final projectId) => projects.firstWhere((p) => p.id == projectId).name,
      };

  Future<void> _editItem([Item? item]) async {
    final defaultProject = view is ProjectView ? (view as ProjectView).projectId : inbox.id;
    final result = await showModalBottomSheet<_ItemEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ItemEditor(
        item: item,
        projects: projects,
        defaultProjectId: defaultProject,
        defaultDue: view is TodayView ? dateOnly(DateTime.now()) : null,
      ),
    );
    if (result == null) return;
    if (result.delete) {
      await db.deleteItem(item!.id);
    } else {
      await db.saveItem(result.item!);
    }
    _reload();
  }

  Future<void> _toggle(Item i) async {
    i.checked = !i.checked;
    i.completedAt = i.checked ? DateTime.now() : null;
    await db.saveItem(i);
    _reload();
  }

  Future<void> _editProject([Project? project]) async {
    final result = await showDialog<Project>(context: context, builder: (_) => ProjectDialog(project: project));
    if (result == null) return;
    await db.saveProject(result);
    setState(() => view = ProjectView(result.id));
    _reload();
  }

  Future<void> _deleteProject(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('All of its tasks will be deleted too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await db.deleteProject(p.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final shown = itemsFor(view, items, DateTime.now(), showCompleted: showCompleted);
    final currentProject = switch (view) {
      ProjectView(:final projectId) => projects.firstWhere((p) => p.id == projectId),
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: showCompleted ? 'Hide completed' : 'Show completed',
            icon: Icon(showCompleted ? Icons.check_circle : Icons.check_circle_outline),
            onPressed: () => setState(() => showCompleted = !showCompleted),
          ),
          if (currentProject != null && !currentProject.inbox)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? _editProject(currentProject) : _deleteProject(currentProject),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit project')),
                PopupMenuItem(value: 'delete', child: Text('Delete project')),
              ],
            ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              _navTile(const TodayView(), Icons.today, 'Today'),
              _navTile(const ScheduledView(), Icons.calendar_month, 'Scheduled'),
              const Divider(),
              for (final p in projects)
                _navTile(
                  ProjectView(p.id),
                  p.inbox ? Icons.inbox : Icons.circle,
                  p.name,
                  color: p.inbox ? null : projectColors[p.color],
                  count: items.where((i) => i.projectId == p.id && !i.checked).length,
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New project'),
                onTap: () {
                  Navigator.pop(context);
                  _editProject();
                },
              ),
            ],
          ),
        ),
      ),
      body: shown.isEmpty
          ? const Center(child: Text('Nothing here. Enjoy your day!'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: shown.length,
              itemBuilder: (_, n) => _itemTile(shown[n]),
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => _editItem(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _navTile(TaskView v, IconData icon, String label, {Color? color, int? count}) {
    final selected = switch ((view, v)) {
      (ProjectView(projectId: final a), ProjectView(projectId: final b)) => a == b,
      _ => view.runtimeType == v.runtimeType,
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: count == null || count == 0 ? null : Text('$count'),
      selected: selected,
      onTap: () {
        setState(() => view = v);
        Navigator.pop(context);
      },
    );
  }

  Widget _itemTile(Item i) {
    final today = dateOnly(DateTime.now());
    final project = projects.where((p) => p.id == i.projectId).firstOrNull;
    final subtitle = [
      if (i.due != null) _dueLabel(i.due!, today, MaterialLocalizations.of(context)),
      if (view is! ProjectView && project != null) project.name,
    ].join(' · ');
    return ListTile(
      leading: Checkbox(
        value: i.checked,
        shape: const CircleBorder(),
        side: BorderSide(color: priorityColors[i.priority]!, width: 2),
        onChanged: (_) => _toggle(i),
      ),
      title: Text(
        i.content,
        style: i.checked ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey) : null,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle,
              style: TextStyle(color: i.due != null && i.due!.isBefore(today) && !i.checked ? Colors.red : null)),
      onTap: () => _editItem(i),
    );
  }
}

String _dueLabel(DateTime due, DateTime today, MaterialLocalizations loc) {
  // UTC so a DST shift (23h day) does not round to the wrong day.
  final diff = DateTime.utc(due.year, due.month, due.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return loc.formatMediumDate(due);
}

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

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: content,
            autofocus: widget.item == null,
            decoration: const InputDecoration(hintText: 'Task name', border: InputBorder.none),
            style: Theme.of(context).textTheme.titleMedium,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          TextField(
            controller: description,
            decoration: const InputDecoration(hintText: 'Description', border: InputBorder.none),
            maxLines: null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InputChip(
                avatar: const Icon(Icons.event, size: 18),
                label: Text(due == null ? 'Date' : loc.formatMediumDate(due!)),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: due ?? now,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (d != null) setState(() => due = d);
                },
                onDeleted: due == null ? null : () => setState(() => due = null),
              ),
              DropdownButton<int>(
                value: priority,
                underline: const SizedBox(),
                items: [
                  for (final p in [4, 3, 2, 1])
                    DropdownMenuItem(
                      value: p,
                      child: Row(children: [
                        Icon(Icons.flag, color: priorityColors[p]),
                        const SizedBox(width: 4),
                        Text(p == 1 ? 'No priority' : 'Priority ${5 - p}'),
                      ]),
                    ),
                ],
                onChanged: (v) => setState(() => priority = v!),
              ),
              DropdownButton<String>(
                value: projectId,
                underline: const SizedBox(),
                items: [
                  for (final p in widget.projects) DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => projectId = v!),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.item != null)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  onPressed: () => Navigator.pop(context, _ItemEdit.delete()),
                ),
              const Spacer(),
              FilledButton(onPressed: _save, child: Text(widget.item == null ? 'Add task' : 'Save')),
            ],
          ),
        ],
      ),
    );
  }
}

class ProjectDialog extends StatefulWidget {
  final Project? project;
  const ProjectDialog({super.key, this.project});

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  late final name = TextEditingController(text: widget.project?.name);
  late String color = widget.project?.color ?? 'blue';

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
      title: Text(widget.project == null ? 'New project' : 'Edit project'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in projectColors.entries)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => color = e.key),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: e.value,
                    child: color == e.key ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
