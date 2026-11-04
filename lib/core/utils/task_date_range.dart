/// Picker bounds are fixed; opening a legacy deadline never changes its draft.
class TaskDateRange {
  static final earliest = DateTime(1900, 1, 1);
  static final latest = DateTime(2999, 12, 31);
  final DateTime initial;
  final DateTime first = earliest;
  final DateTime last = latest;

  TaskDateRange(DateTime deadline) : initial = _clamp(deadline);

  static DateTime _clamp(DateTime deadline) {
    final day = DateTime(deadline.year, deadline.month, deadline.day);
    if (day.isBefore(earliest)) return earliest;
    if (day.isAfter(latest)) return latest;
    return day;
  }
}
