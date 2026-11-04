import 'package:flutter/material.dart';
import 'task_form_keyboard.dart';
import 'picker_actions.dart';
import 'date_digits_formatter.dart';
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
  final _calendarKey = GlobalKey();
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
    if (!_complete(value ?? '')) return null;
    final date = MaterialLocalizations.of(
      context,
    ).parseCompactDate(value ?? '');
    if (date == null) return 'Enter a valid date.';
    if (date.isBefore(widget.firstDate)) {
      return "A bit odd to plan something before you were born, isn't it?";
    }
    if (date.isAfter(widget.lastDate)) {
      return "Trust me, you won't have to worry about this task by then.";
    }
    return null;
  }

  bool _complete(String value) =>
      RegExp(r'^[0-9]{2}/[0-9]{2}/[0-9]{4}$').hasMatch(value);
  bool get _valid =>
      _complete(_controller.text) && _error(_controller.text) == null;

  void _close(DateTime? date) {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.pop(context, date);
  }

  void _toggle() {
    if (_input) {
      if (_valid) {
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

  void _accept() {
    if (_input && !_valid) return;
    _close(
      _input
          ? MaterialLocalizations.of(context).parseCompactDate(_controller.text)
          : _selected,
    );
  }

  void _dateChanged(DateTime date) {
    // CalendarDatePicker also emits onDateChanged when navigating its year list.
    // Accept only the day grid; its public YearPicker is still mounted here
    // until the calendar rebuilds after the year selection callback.
    var choosingYear = false;
    void visit(Element element) {
      if (element.widget is YearPicker) choosingYear = true;
      if (!choosingYear) element.visitChildren(visit);
    }

    _calendarKey.currentContext?.visitChildElements(visit);
    if (choosingYear) {
      setState(() => _selected = date);
    } else {
      _close(date);
    }
  }

  @override
  Widget build(BuildContext context) => TaskFormKeyboard(
    canSubmit: !_closing && (!_input || _valid),
    onSubmit: _accept,
    child: PopScope(
      canPop: !_closing,
      child: IgnorePointer(
        ignoring: _closing,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select date',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_input)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: LimitedTextField(
                          controller: _controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [DateDigitsFormatter()],
                          limit: 10,
                          validationLines: 3,
                          validator: _error,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'Date',
                            hintText: MaterialLocalizations.of(
                              context,
                            ).dateHelpText,
                          ),
                          onSubmitted: (_) => _accept(),
                        ),
                      )
                    else
                      CalendarDatePicker(
                        key: _calendarKey,
                        initialDate: _selected,
                        firstDate: widget.firstDate,
                        lastDate: widget.lastDate,
                        onDateChanged: _dateChanged,
                      ),
                    PickerActions(
                      modeTooltip: _input
                          ? 'Switch to calendar'
                          : 'Switch to input',
                      modeIcon: _input
                          ? Icons.calendar_today_rounded
                          : Icons.edit_outlined,
                      onModeChanged: _closing ? null : _toggle,
                      onCancel: _closing ? null : () => _close(null),
                      showApply: _input,
                      onApply: !_closing && _valid ? _accept : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
