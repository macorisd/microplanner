/// Include an existing deadline even when it lies outside the usual picker range.
class TaskDateRange {
  final DateTime initial;
  final DateTime first;
  final DateTime last;
  TaskDateRange(DateTime deadline, {DateTime? now})
    : initial = DateTime(
        deadline.year.clamp(1, 9999),
        deadline.month,
        deadline.day,
      ),
      first = _first(deadline, now ?? DateTime.now()),
      last = _last(deadline, now ?? DateTime.now());
  static DateTime _first(DateTime deadline, DateTime now) {
    final usual = now.subtract(const Duration(days: 365));
    final date = deadline.isBefore(usual) ? deadline : usual;
    return DateTime(date.year.clamp(1, 9999), date.month, date.day);
  }

  static DateTime _last(DateTime deadline, DateTime now) {
    final usual = now.add(const Duration(days: 365 * 2));
    final date = deadline.isAfter(usual) ? deadline : usual;
    return DateTime(date.year.clamp(1, 9999), date.month, date.day);
  }
}
