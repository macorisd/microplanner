import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../boards/data/board_catalog.dart';

class CategoryDraft {
  const CategoryDraft({
    required this.id,
    required this.name,
    this.icon = 'book',
    this.color = 0xff7986cb,
  });
  final String id;
  final String name;
  final String icon;
  final int color;
  CategoryDraft copyWith({String? name, String? icon, int? color}) =>
      CategoryDraft(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
      );
}

Future<String?> chooseBoardIcon(BuildContext context, String selected) =>
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Choose an icon'),
        content: SizedBox(
          width: 400,
          height: (MediaQuery.sizeOf(context).height * .55).clamp(160, 420),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 5,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final entry in boardIcons.entries)
                IconButton.filledTonal(
                  tooltip: entry.key,
                  isSelected: entry.key == selected,
                  icon: Icon(entry.value),
                  onPressed: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

class ColorChoices extends StatelessWidget {
  const ColorChoices({super.key, required this.color, required this.onChanged});
  final int color;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in boardColors)
        Tooltip(
          message: 'Color ${boardColors.indexOf(value) + 1}',
          child: Semantics(
            button: true,
            selected: value == color,
            label: 'Color ${boardColors.indexOf(value) + 1}',
            child: InkWell(
              onTap: () => onChanged(value),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(value),
                  shape: BoxShape.circle,
                ),
                child: value == color
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            ),
          ),
        ),
    ],
  );
}

Future<CategoryDraft?> editCategory(
  BuildContext context, {
  required String label,
  required bool useIcon,
  CategoryDraft? initial,
}) => showDialog<CategoryDraft>(
  context: context,
  builder: (_) =>
      _CategoryDialog(label: label, useIcon: useIcon, initial: initial),
);

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.label,
    required this.useIcon,
    this.initial,
  });
  final String label;
  final bool useIcon;
  final CategoryDraft? initial;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _controller;
  late String _icon;
  late int _color;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial?.name ?? '');
    _icon = widget.initial?.icon ?? 'book';
    _color = widget.initial?.color ?? boardColors.first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.initial == null ? 'New' : 'Edit'} ${widget.label}'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            const SizedBox(height: 20),
            if (widget.useIcon)
              OutlinedButton.icon(
                onPressed: () async {
                  final chosen = await chooseBoardIcon(context, _icon);
                  if (chosen != null && mounted) setState(() => _icon = chosen);
                },
                icon: Icon(boardIcons[_icon] ?? Icons.label_rounded),
                label: const Text('Choose icon'),
              )
            else ...[
              const Text('Color'),
              const SizedBox(height: 10),
              ColorChoices(
                color: _color,
                onChanged: (value) => setState(() => _color = value),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _controller.text.trim();
          if (name.isEmpty ||
              (name.length > 50 && name != widget.initial?.name)) {
            setState(
              () => _error = name.isEmpty
                  ? 'Enter a name.'
                  : 'Use at most 50 characters.',
            );
            return;
          }
          Navigator.pop(
            context,
            CategoryDraft(
              id: widget.initial?.id ?? const Uuid().v4(),
              name: name,
              icon: _icon,
              color: _color,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class EditableCategoryList extends StatelessWidget {
  const EditableCategoryList({
    super.key,
    required this.title,
    required this.label,
    required this.useIcon,
    required this.items,
    required this.onChanged,
    this.isTemplate = false,
  });
  final String title;
  final String label;
  final bool useIcon;
  final List<CategoryDraft> items;
  final ValueChanged<List<CategoryDraft>> onChanged;
  final bool isTemplate;

  Future<void> _add(BuildContext context) async {
    if (items.length >= 25) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Cannot add $label'),
          content: Text(
            '${isTemplate ? 'A list' : 'A board'} can have up to 25 ${useIcon ? 'task types' : 'subjects'}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final value = await editCategory(context, label: label, useIcon: useIcon);
    if (value != null) onChanged([...items, value]);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            tooltip: 'Add $label',
            onPressed: () => _add(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No ${title.toLowerCase()} yet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: items.length,
        onReorder: (oldIndex, newIndex) {
          final values = [...items];
          if (newIndex > oldIndex) newIndex--;
          values.insert(newIndex, values.removeAt(oldIndex));
          onChanged(values);
        },
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            key: ValueKey(item.id),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              useIcon
                  ? (boardIcons[item.icon] ?? Icons.label_rounded)
                  : Icons.circle,
              color: useIcon ? null : Color(item.color),
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit $label',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final edited = await editCategory(
                      context,
                      label: label,
                      useIcon: useIcon,
                      initial: item,
                    );
                    if (edited != null) {
                      onChanged([
                        for (final value in items)
                          if (value.id == item.id) edited else value,
                      ]);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Remove $label',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onChanged(
                    items.where((value) => value.id != item.id).toList(),
                  ),
                ),
                PopupMenuButton<int>(
                  tooltip: 'Reorder $label',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (direction) {
                    final values = [...items];
                    values.insert(index + direction, values.removeAt(index));
                    onChanged(values);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: -1,
                      enabled: index > 0,
                      child: const Text('Move up'),
                    ),
                    PopupMenuItem(
                      value: 1,
                      enabled: index + 1 < items.length,
                      child: const Text('Move down'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ],
  );
}
