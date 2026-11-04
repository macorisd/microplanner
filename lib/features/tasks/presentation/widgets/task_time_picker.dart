import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/widgets/limited_text_field.dart';
import 'task_form_keyboard.dart';
import 'picker_actions.dart';

Future<TimeOfDay?> showTaskTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TransitionBuilder? builder,
}) => showDialog<TimeOfDay>(
  context: context,
  builder: (context) {
    final child = TaskTimePickerDialog(initialTime: initialTime);
    return builder?.call(context, child) ?? child;
  },
);

/// A clock selection is complete when the minute gesture ends.
class TaskTimePickerDialog extends StatefulWidget {
  const TaskTimePickerDialog({super.key, required this.initialTime});
  final TimeOfDay initialTime;

  @override
  State<TaskTimePickerDialog> createState() => _TaskTimePickerDialogState();
}

class _TaskTimePickerDialogState extends State<TaskTimePickerDialog> {
  late TimeOfDay _time = widget.initialTime;
  final _hour = TextEditingController();
  final _minute = TextEditingController();
  bool _minutes = false;
  bool _input = false;
  bool _closing = false;
  bool _initialized = false;
  bool _settling = false;
  Timer? _selectionTimer;

  bool get _use24 {
    final format = MaterialLocalizations.of(context).timeOfDayFormat();
    return MediaQuery.alwaysUse24HourFormatOf(context) ||
        (format != TimeOfDayFormat.h_colon_mm_space_a &&
            format != TimeOfDayFormat.a_space_h_colon_mm);
  }

  int get _displayHour =>
      _use24 ? _time.hour : (_time.hourOfPeriod == 0 ? 12 : _time.hourOfPeriod);
  int _fullHour(int hour) =>
      _use24 ? hour : hour % 12 + (_time.period == DayPeriod.pm ? 12 : 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _syncInput();
      _hour.addListener(_changed);
      _minute.addListener(_changed);
      _initialized = true;
    }
  }

  void _syncInput() {
    _hour.text = _displayHour.toString().padLeft(2, '0');
    _minute.text = _time.minute.toString().padLeft(2, '0');
  }

  void _changed() => setState(() {});
  String? _hourError(String? value) {
    final hour = int.tryParse(value ?? '');
    return hour == null || hour < (_use24 ? 0 : 1) || hour > (_use24 ? 23 : 12)
        ? (_use24 ? 'Use 0–23.' : 'Use 1–12.')
        : null;
  }

  String? _minuteError(String? value) {
    final minute = int.tryParse(value ?? '');
    return minute == null || minute < 0 || minute > 59 ? 'Use 0–59.' : null;
  }

  bool get _valid =>
      !_input ||
      (_hourError(_hour.text) == null && _minuteError(_minute.text) == null);

  void _close(TimeOfDay? time) {
    if (_closing) return;
    _selectionTimer?.cancel();
    setState(() => _closing = true);
    Navigator.pop(context, time);
  }

  void _accept() {
    if (_closing || _settling || !_valid) return;
    _close(
      _input
          ? TimeOfDay(
              hour: _fullHour(int.parse(_hour.text)),
              minute: int.parse(_minute.text),
            )
          : _time,
    );
  }

  void _select(int value, {required bool complete}) {
    if (_closing || _settling) return;
    setState(
      () => _time = _minutes
          ? _time.replacing(minute: value)
          : _time.replacing(hour: _use24 ? value : _fullHour(value)),
    );
    if (!complete) return;
    final duration = AppMotion.duration(
      context,
      AppMotion.normal + AppMotion.fast,
    );
    void finish() {
      if (!mounted || _closing || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (_minutes) {
        _close(_time);
      } else {
        setState(() {
          _settling = false;
          _minutes = true;
        });
      }
    }

    if (duration == Duration.zero) {
      finish();
      return;
    }
    setState(() => _settling = true);
    _selectionTimer = Timer(duration, finish);
  }

  void _toggleInput() {
    if (_settling) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_input && _valid) {
      _time = TimeOfDay(
        hour: _fullHour(int.parse(_hour.text)),
        minute: int.parse(_minute.text),
      );
    } else if (!_input) {
      _syncInput();
    }
    setState(() => _input = !_input);
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return TaskFormKeyboard(
      canSubmit: !_closing && !_settling && _valid,
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
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      localizations.timePickerDialHelpText,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final hour = _input
                            ? _inputField(
                                _hour,
                                localizations.timePickerHourLabel,
                                _hourError,
                              )
                            : _header(
                                _displayHour.toString().padLeft(2, '0'),
                                localizations.timePickerHourLabel,
                                !_minutes,
                                () {
                                  if (!_settling) {
                                    setState(() => _minutes = false);
                                  }
                                },
                              );
                        final minute = _input
                            ? _inputField(
                                _minute,
                                localizations.timePickerMinuteLabel,
                                _minuteError,
                              )
                            : _header(
                                _time.minute.toString().padLeft(2, '0'),
                                localizations.timePickerMinuteLabel,
                                _minutes,
                                () {
                                  if (!_settling) {
                                    setState(() => _minutes = true);
                                  }
                                },
                              );
                        return Column(
                          children: [
                            if (_input && constraints.maxWidth < 280) ...[
                              hour,
                              const SizedBox(height: 16),
                              minute,
                            ] else
                              Row(
                                children: [
                                  Expanded(child: hour),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ).copyWith(
                                          bottom: _input
                                              ? LimitedTextField.supportingHeightOf(
                                                  context,
                                                )
                                              : 0,
                                        ),
                                    child: Text(
                                      ':',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineLarge,
                                    ),
                                  ),
                                  Expanded(child: minute),
                                ],
                              ),
                            if (!_use24)
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final period in DayPeriod.values)
                                    ChoiceChip(
                                      label: Text(
                                        period == DayPeriod.am
                                            ? localizations
                                                  .anteMeridiemAbbreviation
                                            : localizations
                                                  .postMeridiemAbbreviation,
                                      ),
                                      selected: _time.period == period,
                                      onSelected: _settling
                                          ? null
                                          : (_) => setState(
                                              () => _time = _time.replacing(
                                                hour:
                                                    _time.hour % 12 +
                                                    (period == DayPeriod.pm
                                                        ? 12
                                                        : 0),
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    if (!_input)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 256),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: LayoutBuilder(
                              builder: (context, constraints) => IgnorePointer(
                                ignoring: _settling,
                                child: _TimeDial(
                                  size: constraints.maxWidth,
                                  minutes: _minutes,
                                  use24: _use24,
                                  settling: _settling,
                                  value: _minutes ? _time.minute : _time.hour,
                                  onChanged: _select,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    PickerActions(
                      modeTooltip: _input
                          ? 'Switch to dial'
                          : 'Switch to input',
                      modeIcon: _input
                          ? Icons.access_time
                          : Icons.keyboard_outlined,
                      onModeChanged: _closing || _settling
                          ? null
                          : _toggleInput,
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
    );
  }

  Widget _inputField(
    TextEditingController controller,
    String label,
    String? Function(String?) validator,
  ) => LimitedTextField(
    controller: controller,
    limit: 2,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    validator: validator,
    decoration: InputDecoration(labelText: label),
    onSubmitted: (_) => _accept(),
  );

  Widget _header(
    String text,
    String label,
    bool selected,
    VoidCallback onPressed,
  ) => Semantics(
    label: label,
    selected: selected,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: FittedBox(
        child: Text(text, style: Theme.of(context).textTheme.displaySmall),
      ),
    ),
  );
}

class _TimeDial extends StatefulWidget {
  const _TimeDial({
    required this.size,
    required this.minutes,
    required this.use24,
    required this.settling,
    required this.value,
    required this.onChanged,
  });
  final double size;
  final bool minutes;
  final bool use24;
  final bool settling;
  final int value;
  final void Function(int value, {required bool complete}) onChanged;

  @override
  State<_TimeDial> createState() => _TimeDialState();
}

class _TimeDialState extends State<_TimeDial>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this, value: 1);
  late double _fromAngle = _angle;
  late double _toAngle = _angle;
  late double _fromRadius = _radius;
  late double _toRadius = _radius;
  bool _hold = false;

  double get size => widget.size;
  bool get minutes => widget.minutes;
  bool get use24 => widget.use24;
  int get value => widget.value;
  void Function(int, {required bool complete}) get onChanged =>
      widget.onChanged;
  double get _angle =>
      (minutes ? value / 60 : value / 12) * math.pi * 2 - math.pi / 2;
  double get _radius =>
      !minutes && use24 && (value == 0 || value > 12) ? .26 : .40;
  double get _progress => _hold
      ? Interval(
          0,
          AppMotion.normal.inMilliseconds /
              (AppMotion.normal + AppMotion.fast).inMilliseconds,
          curve: AppMotion.curve,
        ).transform(_motion.value)
      : AppMotion.curve.transform(_motion.value);
  double get _paintAngle => _fromAngle + (_toAngle - _fromAngle) * _progress;
  double get _paintRadius =>
      _fromRadius + (_toRadius - _fromRadius) * _progress;

  @override
  void didUpdateWidget(_TimeDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == value &&
        oldWidget.minutes == minutes &&
        oldWidget.use24 == use24 &&
        oldWidget.settling == widget.settling) {
      return;
    }
    final from = _paintAngle;
    _fromRadius = _paintRadius;
    _fromAngle = from;
    // Take the shortest arc, including across midnight and the 59/00 boundary.
    _toAngle = from + (_angle - from + math.pi) % (2 * math.pi) - math.pi;
    _toRadius = _radius;
    _hold = widget.settling;
    _motion.duration = AppMotion.duration(
      context,
      _hold ? AppMotion.normal + AppMotion.fast : AppMotion.normal,
    );
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  int _valueAt(Offset point) {
    final offset = point - Offset(size / 2, size / 2);
    final fraction =
        ((math.atan2(offset.dy, offset.dx) + math.pi / 2) / (2 * math.pi)) % 1;
    if (minutes) return (fraction * 60).round() % 60;
    final hour = (fraction * 12).round() % 12;
    if (!use24) return hour == 0 ? 12 : hour;
    final inner = offset.distance < size * .32;
    return inner ? (hour == 0 ? 0 : hour + 12) : (hour == 0 ? 12 : hour);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = minutes
        ? List.generate(12, (i) => i * 5)
        : List.generate(use24 ? 24 : 12, (i) => use24 ? i : i + 1);
    return GestureDetector(
      key: const ValueKey('time-dial'),
      behavior: HitTestBehavior.opaque,
      onTapUp: (event) =>
          onChanged(_valueAt(event.localPosition), complete: true),
      onPanStart: (event) =>
          onChanged(_valueAt(event.localPosition), complete: false),
      onPanUpdate: (event) =>
          onChanged(_valueAt(event.localPosition), complete: false),
      onPanEnd: (_) => onChanged(
        minutes ? value : (use24 ? value : (value % 12 == 0 ? 12 : value % 12)),
        complete: true,
      ),
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, child) => CustomPaint(
          painter: _DialPainter(
            angle: _paintAngle,
            radius: _paintRadius,
            colors: colors,
          ),
          child: child,
        ),
        child: Stack(
          children: [
            for (final number in values)
              Builder(
                builder: (context) {
                  final inner =
                      !minutes && use24 && (number == 0 || number > 12);
                  final radius = size * (inner ? .26 : .40);
                  final angle =
                      (minutes ? number / 60 : number / 12) * math.pi * 2 -
                      math.pi / 2;
                  final selected = minutes
                      ? number == value
                      : (use24 ? number == value : number % 12 == value % 12);
                  return Positioned(
                    left: size / 2 + math.cos(angle) * radius - 20,
                    top: size / 2 + math.sin(angle) * radius - 20,
                    width: 40,
                    height: 40,
                    child: Semantics(
                      label: '${minutes ? 'Minute' : 'Hour'} $number',
                      selected: selected,
                      button: true,
                      onTap: () => onChanged(number, complete: true),
                      child: IgnorePointer(
                        child: TextButton(
                          key: ValueKey(
                            '${minutes ? 'minute' : 'hour'}-$number',
                          ),
                          onPressed: () => onChanged(number, complete: true),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: selected
                                ? colors.onPrimary
                                : colors.onSurface,
                          ),
                          child: Text(
                            minutes || (use24 && inner)
                                ? number.toString().padLeft(2, '0')
                                : '$number',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.angle,
    required this.radius,
    required this.colors,
  });
  final double angle;
  final double radius;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()..color = AppColors.surfaceVariant;
    canvas.drawCircle(center, size.width / 2, paint);
    final end =
        center + Offset(math.cos(angle), math.sin(angle)) * size.width * radius;
    paint
      ..color = colors.primary
      ..strokeWidth = 2;
    canvas.drawLine(center, end, paint);
    canvas.drawCircle(center, 4, paint);
    canvas.drawCircle(end, 20, paint);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      angle != old.angle || radius != old.radius || colors != old.colors;
}
