// Settings tab: the entries of Planify desktop's main menu (MainWindow.build_menu_app).
import 'package:flutter/material.dart';

import 'main.dart';
import 'models.dart';

/// Rounded group of rows, like an Adwaita boxed list.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group(this.children);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: pal.popover,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(),
            c,
          ],
        ],
      ),
    );
  }
}

Widget _row(
  BuildContext context,
  IconData icon,
  String title,
  VoidCallback onTap, {
  String? subtitle,
}) => ListTile(
  leading: Icon(icon, color: accent),
  title: Text(title),
  subtitle: subtitle == null ? null : Text(subtitle),
  trailing: Icon(Icons.chevron_right, color: Pal.of(context).dim),
  onTap: onTap,
);

Widget _page(BuildContext context, String title, List<Widget> children) =>
    Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        // the list scrolls under the floating tab bar; its padding clears it
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: children,
      ),
    );

void _push(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

class SettingsPage extends StatelessWidget {
  final AppState state;
  const SettingsPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) => _page(context, 'Settings', [
    _Group([
      _row(
        context,
        Icons.tune,
        'Preferences',
        () => _push(context, PreferencesPage(state: state)),
      ),
    ]),
    _Group([
      _row(
        context,
        Icons.insights_outlined,
        'Summary & Productivity',
        () => _push(context, SummaryPage(state: state)),
      ),
    ]),
    _Group([
      _row(
        context,
        Icons.info_outline,
        'About Planify',
        () => showAboutDialog(
          context: context,
          applicationName: 'Planify',
          applicationVersion: '1.0.0', // ponytail: keep in sync with pubspec.yaml; use package_info_plus if it drifts
          applicationLegalese:
              'By Alain\nhttps://github.com/alainm23/planify\nGPL-3.0',
        ),
      ),
    ]),
  ]);
}

/// Desktop Preferences pages that apply to this app; for now only the CalDAV account.
class PreferencesPage extends StatelessWidget {
  final AppState state;
  const PreferencesPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _page(context, 'Preferences', [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          'Accounts',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Pal.of(context).dim,
          ),
        ),
      ),
      _Group([
        _row(
          context,
          state.syncError == null
              ? Icons.cloud_outlined
              : Icons.cloud_off_outlined,
          'CalDAV',
          () => showDialog(
            context: context,
            builder: (_) => SyncDialog(state: state),
          ),
          subtitle: state.syncError ?? (state.syncing ? 'Syncing…' : null),
        ),
      ]),
    ]),
  );
}

/// Summary section of desktop's Summary & Productivity dialog (SummarySection.vala).
class SummaryPage extends StatelessWidget {
  final AppState state;
  const SummaryPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final pal = Pal.of(context);
      final today = dateOnly(DateTime.now());
      final total = state.items.length;
      final completed = state.items.where((i) => i.checked).length;
      final overdue = state.items
          .where((i) => !i.checked && i.due != null && i.due!.isBefore(today))
          .length;
      final progress = total == 0 ? 0.0 : completed / total;

      Widget card(int n, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: pal.popover,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: pal.border),
          ),
          child: Column(
            children: [
              Text(
                '$n',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(label, style: TextStyle(fontSize: 12, color: pal.dim)),
            ],
          ),
        ),
      );

      return _page(context, 'Summary & Productivity', [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            'Summary',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            card(total, 'Total'),
            card(total - completed, 'Pending'),
            card(completed, 'Completed'),
            card(overdue, 'Overdue'),
          ],
        ),
        const SizedBox(height: 12),
        _Group([
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              spacing: 6,
              children: [
                Row(
                  children: [
                    const Text('Progress', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(fontSize: 13, color: pal.dim),
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: accent,
                  backgroundColor: pal.border,
                ),
              ],
            ),
          ),
        ]),
      ]);
    },
  );
}
