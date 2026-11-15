import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/notifications/notification_preferences.dart';
import '../../../../core/widgets/disclosure_icon.dart';
import '../../../../core/widgets/limited_text_field.dart';
import 'form_dialog.dart';
import 'task_form_keyboard.dart';

const reminderPresets = [15, 30, 60, 180, 1440, 2880, 10080];

class ReminderSelector extends StatefulWidget {
  final int? value;
  final int defaultMinutes;
  final ValueChanged<int?>? onChanged;
  final bool allowDefault;
  final String label;
  const ReminderSelector({
    super.key,
    required this.value,
    required this.defaultMinutes,
    required this.onChanged,
    this.allowDefault = true,
    this.label = 'Reminder',
  });
  @override
  State<ReminderSelector> createState() => _ReminderSelectorState();
}

class _ReminderSelectorState extends State<ReminderSelector> {
  bool _picking = false;
  int _revision = 0;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey(
      '${widget.label}:${widget.value}:${widget.defaultMinutes}:$_revision',
    ),
    initialValue: widget.value?.toString() ?? 'default',
    isExpanded: true,
    decoration: InputDecoration(labelText: widget.label),
    icon: const DisclosureIcon(),
    items: [
      if (widget.allowDefault)
        DropdownMenuItem(
          value: 'default',
          child: Text(
            'Use default (${reminderDuration(widget.defaultMinutes)} before)',
          ),
        ),
      if (widget.allowDefault)
        const DropdownMenuItem(value: '0', child: Text('No reminder')),
      for (final minutes in {
        ...reminderPresets,
        if (widget.value != null && widget.value! > 0) widget.value!,
      }.toList()..sort())
        DropdownMenuItem(
          value: minutes.toString(),
          child: Text('${reminderDuration(minutes)} before'),
        ),
      const DropdownMenuItem(value: 'custom', child: Text('Custom…')),
    ],
    onChanged: widget.onChanged == null
        ? null
        : (value) async {
            FocusManager.instance.primaryFocus?.unfocus();
            if (value == 'custom') {
              if (_picking) return;
              _picking = true;
              final minutes = await showDialog<int>(
                context: context,
                builder: (_) => DurationEditor(
                  minutes: widget.value ?? widget.defaultMinutes,
                ),
              );
              _picking = false;
              if (!mounted) return;
              setState(() => _revision++);
              if (minutes != null) {
                widget.onChanged!(minutes);
              } else {
                setState(() {});
              }
            } else {
              widget.onChanged!(value == 'default' ? null : int.parse(value!));
            }
          },
  );
}

class DurationEditor extends StatefulWidget {
  final int minutes;
  const DurationEditor({super.key, required this.minutes});
  @override
  State<DurationEditor> createState() => _DurationEditorState();
}

class _DurationEditorState extends State<DurationEditor> {
  late final TextEditingController _value;
  int _unit = 1;
  @override
  void initState() {
    super.initState();
    _unit = widget.minutes % 1440 == 0
        ? 1440
        : widget.minutes % 60 == 0
        ? 60
        : 1;
    _value = TextEditingController(text: '${widget.minutes ~/ _unit}')
      ..addListener(_changed);
  }

  void _changed() => setState(() {});
  int? get minutes {
    final n = int.tryParse(_value.text);
    if (n == null || n * _unit < 1 || n * _unit > 10080) return null;
    return n * _unit;
  }

  void _save() {
    if (minutes != null && minutes != widget.minutes) {
      Navigator.pop(context, minutes);
    }
  }

  @override
  Widget build(BuildContext context) => TaskFormKeyboard(
    canSubmit: minutes != null && minutes != widget.minutes,
    onSubmit: _save,
    child: FormDialog(
      title: const Text('Custom reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LimitedTextField(
            controller: _value,
            limit: 5,
            validationLines: 2,
            errorText: minutes == null
                ? 'Choose a duration from 1 minute to 7 days.'
                : null,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Notify before deadline',
            ),
            validator: (_) => minutes == null
                ? 'Choose a duration from 1 minute to 7 days.'
                : null,
            onSubmitted: (_) => _save(),
          ),
          DropdownButtonFormField<int>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            icon: const DisclosureIcon(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Minutes')),
              DropdownMenuItem(value: 60, child: Text('Hours')),
              DropdownMenuItem(value: 1440, child: Text('Days')),
            ],
            onChanged: (value) => setState(() => _unit = value!),
          ),
          const SizedBox(height: 16),
          const Text('Choose a duration from 1 minute to 7 days.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: minutes != null && minutes != widget.minutes
              ? _save
              : null,
          child: const Text('Save changes'),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }
}
