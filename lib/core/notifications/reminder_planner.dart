import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import '../data/workspace_snapshot.dart';
import 'notification_preferences.dart';

class ReminderEvent {
  final String key, owner, taskId, boardId, title, body;
  final DateTime at, deadline, expires;
  final bool atDeadline;
  const ReminderEvent({
    required this.key,
    required this.owner,
    required this.taskId,
    required this.boardId,
    required this.title,
    required this.body,
    required this.at,
    required this.deadline,
    required this.expires,
    required this.atDeadline,
  });
  int get proposedId =>
      int.parse(
        sha256.convert(utf8.encode(key)).toString().substring(0, 8),
        radix: 16,
      ) &
      0x7fffffff;
  String get payload =>
      jsonEncode({'owner': owner, 'task': taskId, 'board': boardId});
  Map<String, dynamic> native(int id) => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'deadline': deadline.millisecondsSinceEpoch,
    'expires': expires.millisecondsSinceEpoch,
    'atDeadline': atDeadline,
    'title': title,
    'body': body,
    'payload': payload,
  };
  String get fingerprint => jsonEncode([
    at.millisecondsSinceEpoch,
    title,
    body,
    payload,
    expires.millisecondsSinceEpoch,
  ]);
}

/// Pure planning uses exact deadline instants and the device's local quiet clock.
List<ReminderEvent> planReminders({
  required WorkspaceSnapshot workspace,
  required String owner,
  required DateTime now,
  required DateTime expires,
  required DeviceNotificationPreferences device,
  Set<String> suppressed = const {},
}) {
  if (!device.enabled || !expires.isAfter(now)) return [];
  final preferences =
      workspace.notificationPreferences ?? const NotificationPreferences();
  final boards = {for (final b in workspace.boards) b.id: b.name};
  final events = <ReminderEvent>[];
  for (final task in workspace.tasks) {
    if (task.isCompleted ||
        task.reminderMinutes == 0 ||
        suppressed.contains(task.id) ||
        !task.deadline.isAfter(now) ||
        !boards.containsKey(task.boardId)) {
      continue;
    }
    for (final atDeadline in [false, if (preferences.atDeadline) true]) {
      var at = atDeadline
          ? task.deadline
          : task.deadline.subtract(
              Duration(
                minutes: task.reminderMinutes ?? preferences.advanceMinutes,
              ),
            );
      if (at.isBefore(now)) at = now;
      if (device.quietHours) {
        final local = at.toLocal();
        final minute = local.hour * 60 + local.minute;
        final start = device.quietStart, end = device.quietEnd;
        final quiet = start < end
            ? minute >= start && minute < end
            : minute >= start || minute < end;
        if (quiet) {
          if (atDeadline) continue;
          final tomorrow = start > end && minute >= start;
          at = DateTime(
            local.year,
            local.month,
            local.day + (tomorrow ? 1 : 0),
            end ~/ 60,
            end % 60,
          );
          if (!at.isBefore(task.deadline)) continue;
        }
      }
      if (!at.isBefore(expires)) continue;
      events.add(
        ReminderEvent(
          key:
              '$owner:${task.id}:${task.deadline.toUtc().toIso8601String()}:${atDeadline ? 'deadline' : 'advance'}',
          owner: owner,
          taskId: task.id,
          boardId: task.boardId!,
          title: device.showDetails ? task.name : 'microplanner',
          body: device.showDetails
              ? '${boards[task.boardId]} · Due ${DateFormat('EEE d MMM, HH:mm').format(task.deadline.toLocal())}'
              : 'A task deadline is approaching.',
          at: at,
          deadline: task.deadline,
          expires: expires,
          atDeadline: atDeadline,
        ),
      );
    }
  }
  events.sort((a, b) {
    final time = a.at.compareTo(b.at);
    return time != 0 ? time : a.key.compareTo(b.key);
  });
  return events;
}
