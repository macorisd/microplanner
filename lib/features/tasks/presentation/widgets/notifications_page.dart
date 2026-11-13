import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/notifications/notification_controller.dart';
import '../../../../core/notifications/notification_preferences.dart';
import '../../../../core/data/workspace_controller.dart';
import 'reminder_selector.dart';
import 'task_time_picker.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _picking = false;
  Future<void> _time(NotificationController controller, bool start) async {
    if (_picking) return;
    _picking = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final minutes = start
        ? controller.device.quietStart
        : controller.device.quietEnd;
    final value = await showTaskTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    _picking = false;
    if (value == null || !mounted) return;
    final next = value.hour * 60 + value.minute;
    if (next ==
        (start ? controller.device.quietEnd : controller.device.quietStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose different start and end times.')),
      );
      return;
    }
    await controller.updateDevice(
      controller.device.copyWith(
        quietStart: start ? next : null,
        quietEnd: start ? null : next,
      ),
    );
  }

  String _label(BuildContext context, int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();
    final workspace = context.watch<WorkspaceController>();
    final preferences =
        (workspace.outbox?.projected ?? workspace.snapshot)
            .notificationPreferences ??
        const NotificationPreferences();
    final device = controller.device;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Reminders use the last tasks synchronized on this device. Enable each device separately.',
        ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable notifications on this device'),
          value: device.enabled,
          onChanged: controller.busy
              ? null
              : (value) async {
                  final android =
                      Theme.of(context).platform == TargetPlatform.android;
                  final saved = await controller.updateDevice(
                    device.copyWith(enabled: value),
                  );
                  if (mounted &&
                      saved &&
                      value &&
                      android &&
                      controller.permitted &&
                      !controller.precise) {
                    await controller.adapter.settings(exact: true);
                  }
                },
        ),
        const SizedBox(height: 16),
        ReminderSelector(
          value: preferences.advanceMinutes,
          defaultMinutes: 1440,
          allowDefault: false,
          label: 'Default reminder',
          onChanged: workspace.canWrite
              ? (minutes) => controller.updateDefaults(
                  NotificationPreferences(
                    advanceMinutes: minutes!,
                    atDeadline: preferences.atDeadline,
                  ),
                )
              : null,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also remind at the deadline'),
          value: preferences.atDeadline,
          onChanged: workspace.canWrite
              ? (value) => controller.updateDefaults(
                  NotificationPreferences(
                    advanceMinutes: preferences.advanceMinutes,
                    atDeadline: value,
                  ),
                )
              : null,
        ),
        const Text(
          'Timing defaults sync across your account. Existing tasks follow them unless they have their own reminder.',
        ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Quiet hours'),
          value: device.quietHours,
          onChanged: controller.busy
              ? null
              : (value) =>
                    controller.updateDevice(device.copyWith(quietHours: value)),
        ),
        if (device.quietHours) ...[
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: controller.busy
                    ? null
                    : () => _time(controller, true),
                child: Text('From ${_label(context, device.quietStart)}'),
              ),
              TextButton(
                onPressed: controller.busy
                    ? null
                    : () => _time(controller, false),
                child: Text('Until ${_label(context, device.quietEnd)}'),
              ),
            ],
          ),
          const Text(
            'Advance reminders wait until quiet hours end, only before the deadline. Deadline reminders during quiet hours are skipped.',
          ),
        ],
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show task details'),
          subtitle: const Text(
            'Turn off to hide task titles, boards and deadlines in notifications.',
          ),
          value: device.showDetails,
          onChanged: controller.busy
              ? null
              : (value) => controller.updateDevice(
                  device.copyWith(showDetails: value),
                ),
        ),
        const SizedBox(height: 16),
        Text(
          controller.error ??
              (!device.enabled
                  ? 'Notifications are off on this device.'
                  : !controller.permitted
                  ? 'Notifications are blocked in system settings.'
                  : !controller.precise
                  ? 'Timing is approximate. Android can delay reminders by up to an hour, or longer with battery restrictions. Short deadlines may be missed. Allow precise reminders for alerts at the selected time.'
                  : 'Notifications are enabled.'),
        ),
        if (device.enabled && controller.permitted)
          Text(
            '${controller.scheduled} reminders scheduled. Reopen microplanner to refresh coverage and changes from other devices.',
          ),
        if (controller.eligible > 200)
          const Text(
            'Only the nearest 200 reminders are scheduled. Reopen microplanner to schedule more.',
          ),
        if (device.enabled && controller.outsideSession > 0)
          const Text(
            'Some reminders fall beyond your current sign-in session. Sign in again before they are due to extend coverage.',
          ),
        if (controller.error != null)
          TextButton(
            onPressed: controller.reconcile,
            child: const Text('Try again'),
          ),
        if (!controller.precise &&
            device.enabled &&
            Theme.of(context).platform == TargetPlatform.android)
          TextButton(
            onPressed: () => controller.adapter.settings(exact: true),
            child: const Text('Allow precise reminders'),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => controller.adapter.settings(),
              child: const Text('Open system notification settings'),
            ),
            TextButton(
              onPressed: controller.permitted ? controller.test : null,
              child: const Text('Send test notification'),
            ),
          ],
        ),
        const Text(
          'Sound, vibration, banners and Do Not Disturb follow system settings. The test can run during quiet hours.',
        ),
      ],
    );
  }
}
