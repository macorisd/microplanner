import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../boards/data/board_catalog.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/widgets/limited_text_field.dart';
import '../../../../core/widgets/bounded_reorderable_list.dart';
import 'editor_panel.dart';

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

bool sameCategories(List<CategoryDraft> a, List<CategoryDraft> b) =>
    a.length == b.length &&
    List.generate(
      a.length,
      (i) =>
          a[i].id == b[i].id &&
          a[i].name == b[i].name &&
          a[i].icon == b[i].icon &&
          a[i].color == b[i].color,
    ).every((value) => value);

Future<String?> chooseBoardIcon(BuildContext context, String selected) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final result = await showMotionDialog<String>(
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
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (context.mounted) FocusScope.of(context).unfocus();
  return result;
}

class IconChoice extends StatelessWidget {
  const IconChoice({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.labelStyle,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: labelStyle),
      const SizedBox(height: AppTheme.spacingSmall),
      IconButton.outlined(
        tooltip: 'Choose ${label.toLowerCase()}',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: color,
          backgroundColor: boardRowBackground(color),
          side: BorderSide(color: color.withValues(alpha: .45)),
          minimumSize: const Size.square(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
        ),
        icon: Icon(icon, size: 24),
      ),
    ],
  );
}

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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(value),
                  shape: BoxShape.circle,
                ),
                child: value == color
                    ? Icon(
                        Icons.check,
                        color: Color(value).computeLuminance() > .5
                            ? AppColors.textPrimary
                            : Colors.white,
                        size: 20,
                      )
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
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final result = await showMotionDialog<CategoryDraft>(
    context: context,
    builder: (_) =>
        _CategoryDialog(label: label, useIcon: useIcon, initial: initial),
  );
  if (context.mounted) FocusScope.of(context).unfocus();
  return result;
}

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
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial?.name ?? '');
    _icon = widget.initial?.icon ?? 'book';
    _color = widget.initial?.color ?? boardColors.first;
    _controller.addListener(_changed);
  }

  void _changed() {
    setState(() => _error = null);
  }

  bool get _hasChanges =>
      widget.initial == null ||
      _controller.text.trim() != widget.initial!.name ||
      _icon != widget.initial!.icon ||
      _color != widget.initial!.color;
  bool get _canSave =>
      !_closing &&
      _hasChanges &&
      _controller.text.trim().isNotEmpty &&
      (_controller.text.trim().length <= WorkspaceLimits.categoryName ||
          _controller.text.trim() == widget.initial?.name);
  void _save() {
    if (!_canSave) return;
    setState(() => _closing = true);
    Navigator.pop(
      context,
      CategoryDraft(
        id: widget.initial?.id ?? const Uuid().v4(),
        name: _controller.text.trim(),
        icon: _icon,
        color: _color,
      ),
    );
  }

  void _close() {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorPanel(
    dialog: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorHeading(
          title: '${widget.initial == null ? 'New' : 'Edit'} ${widget.label}',
          icon: widget.useIcon
              ? Icons.label_outline_rounded
              : Icons.circle_outlined,
          onClose: _closing ? null : _close,
        ),
        const SizedBox(height: AppTheme.spacingLarge),
        LimitedTextField(
          controller: _controller,
          limit: WorkspaceLimits.categoryName,
          validator: (_) => _error,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: 'Name', errorText: _error),
        ),
        const SizedBox(height: 20),
        if (widget.useIcon)
          IconChoice(
            label: 'Icon',
            color: AppColors.primary,
            onPressed: () async {
              final chosen = await chooseBoardIcon(context, _icon);
              if (chosen != null && mounted) setState(() => _icon = chosen);
            },
            icon: boardIcons[_icon] ?? Icons.label_rounded,
          )
        else ...[
          const Text('Color'),
          const SizedBox(height: 10),
          ColorChoices(
            color: _color,
            onChanged: (value) => setState(() => _color = value),
          ),
        ],
        const SizedBox(height: AppTheme.spacingLarge),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: _closing ? null : _close,
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _canSave ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
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
      BoundedReorderableList(
        itemCount: items.length,
        onReorder: (oldIndex, newIndex) {
          final values = [...items];
          if (newIndex > oldIndex) newIndex--;
          values.insert(newIndex, values.removeAt(oldIndex));
          onChanged(values);
        },
        itemBuilder: (context, index) {
          final item = items[index];
          Future<void> editItem() async {
            final edited = await editCategory(
              context,
              label: label,
              useIcon: useIcon,
              initial: item,
            );
            if (edited != null && context.mounted) {
              onChanged([
                for (final value in items)
                  if (value.id == item.id) edited else value,
              ]);
            }
          }

          return Padding(
            key: ValueKey(item.id),
            padding: const EdgeInsets.only(bottom: 4),
            child: Tooltip(
              message: 'Edit $label',
              child: Material(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: editItem,
                  contentPadding: const EdgeInsets.only(left: 12, right: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  visualDensity: VisualDensity.standard,
                  titleAlignment: ListTileTitleAlignment.center,
                  minLeadingWidth:
                      Theme.of(context).platform == TargetPlatform.windows
                      ? 24
                      : 20,
                  horizontalTitleGap:
                      Theme.of(context).platform == TargetPlatform.windows
                      ? AppTheme.spacingMedium
                      : AppTheme.spacingSmall,
                  leading: SizedBox.square(
                    dimension:
                        Theme.of(context).platform == TargetPlatform.windows
                        ? 24
                        : 20,
                    child: Center(
                      child: Icon(
                        useIcon
                            ? (boardIcons[item.icon] ?? Icons.label_rounded)
                            : Icons.circle,
                        size: 20,
                        color: useIcon ? AppColors.primary : Color(item.color),
                      ),
                    ),
                  ),
                  title: Tooltip(
                    message: item.name,
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const SizedBox(
                          width: 28,
                          height: 48,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove $label',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onChanged(
                          items.where((value) => value.id != item.id).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}
