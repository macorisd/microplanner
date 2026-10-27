import 'package:flutter/material.dart';
import '../../../../core/widgets/limited_text_field.dart';

Future<DateTime?> showTaskDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required Locale locale,
  required DatePickerEntryMode initialEntryMode,
  TransitionBuilder? builder,
}) => showDialog<DateTime>(
  context: context,
  builder: (context) {
    final child = Localizations.override(
      context: context,
      locale: locale,
      child: TaskDatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        input: initialEntryMode == DatePickerEntryMode.inputOnly,
      ),
    );
    return builder?.call(context, child) ?? child;
  },
);

/// The calendar and bounded manual entry share the same validated date range.
class TaskDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool input;
  const TaskDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.input = false,
  });
  @override
  State<TaskDatePickerDialog> createState() => _TaskDatePickerDialogState();
}

class _TaskDatePickerDialogState extends State<TaskDatePickerDialog> {
  late DateTime _selected = widget.initialDate;
  late bool _input = widget.input;
  final _controller = TextEditingController();
  bool _initialized = false;
  bool _closing = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _controller.text = MaterialLocalizations.of(
        context,
      ).formatCompactDate(_selected);
      _controller.addListener(_textChanged);
      _initialized = true;
    }
  }

  void _textChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _error(String? value) {
    if ((value?.length ?? 0) > 10) return 'Use at most 10 characters.';
    final date = MaterialLocalizations.of(
      context,
    ).parseCompactDate(value ?? '');
    if (date == null) return 'Enter a valid date.';
    if (date.isBefore(widget.firstDate) || date.isAfter(widget.lastDate)) {
      final localizations = MaterialLocalizations.of(context);
      return 'Use a date from ${localizations.formatCompactDate(widget.firstDate)} to ${localizations.formatCompactDate(widget.lastDate)}.';
    }
    return null;
  }

  void _close(DateTime? date) {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.pop(context, date);
  }

  void _toggle() {
    if (_input) {
      if (_error(_controller.text) == null) {
        _selected = MaterialLocalizations.of(
          context,
        ).parseCompactDate(_controller.text)!;
      }
    } else {
      _controller.text = MaterialLocalizations.of(
        context,
      ).formatCompactDate(_selected);
    }
    setState(() => _input = !_input);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_closing,
    child: IgnorePointer(
      ignoring: _closing,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select date',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: _input
                            ? 'Switch to calendar'
                            : 'Switch to input',
                        onPressed: _closing ? null : _toggle,
                        icon: Icon(
                          _input
                              ? Icons.calendar_today_rounded
                              : Icons.edit_outlined,
                        ),
                      ),
                    ],
                  ),
                  if (_input)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: LimitedTextField(
                        controller: _controller,
                        keyboardType: TextInputType.datetime,
                        limit: 10,
                        validator: _error,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Date',
                          hintText: MaterialLocalizations.of(
                            context,
                          ).dateHelpText,
                        ),
                        onSubmitted: (_) {
                          if (_error(_controller.text) == null) {
                            _close(
                              MaterialLocalizations.of(
                                context,
                              ).parseCompactDate(_controller.text),
                            );
                          }
                        },
                      ),
                    )
                  else
                    CalendarDatePicker(
                      initialDate: _selected,
                      firstDate: widget.firstDate,
                      lastDate: widget.lastDate,
                      onDateChanged: (value) =>
                          setState(() => _selected = value),
                    ),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _closing ? null : () => _close(null),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                        ),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed:
                            _closing ||
                                (_input && _error(_controller.text) != null)
                            ? null
                            : () => _close(
                                _input
                                    ? MaterialLocalizations.of(
                                        context,
                                      ).parseCompactDate(_controller.text)
                                    : _selected,
                              ),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
