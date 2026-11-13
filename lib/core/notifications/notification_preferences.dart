class NotificationPreferences {
  final int advanceMinutes;
  final bool atDeadline;
  const NotificationPreferences({
    this.advanceMinutes = 1440,
    this.atDeadline = false,
  });
  factory NotificationPreferences.fromJson(Map<String, dynamic>? json) =>
      NotificationPreferences(
        advanceMinutes: json?['advanceMinutes'] as int? ?? 1440,
        atDeadline: json?['atDeadline'] as bool? ?? false,
      );
  Map<String, dynamic> toJson() => {
    'advanceMinutes': advanceMinutes,
    'atDeadline': atDeadline,
  };
}

class DeviceNotificationPreferences {
  final bool enabled, quietHours, showDetails;
  final int quietStart, quietEnd;
  const DeviceNotificationPreferences({
    this.enabled = false,
    this.quietHours = false,
    this.showDetails = true,
    this.quietStart = 1320,
    this.quietEnd = 480,
  });
  factory DeviceNotificationPreferences.fromJson(Map<String, dynamic> json) =>
      DeviceNotificationPreferences(
        enabled: json['enabled'] == true,
        quietHours: json['quietHours'] == true,
        showDetails: json['showDetails'] != false,
        quietStart: json['quietStart'] as int? ?? 1320,
        quietEnd: json['quietEnd'] as int? ?? 480,
      );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'quietHours': quietHours,
    'showDetails': showDetails,
    'quietStart': quietStart,
    'quietEnd': quietEnd,
  };
  DeviceNotificationPreferences copyWith({
    bool? enabled,
    bool? quietHours,
    bool? showDetails,
    int? quietStart,
    int? quietEnd,
  }) => DeviceNotificationPreferences(
    enabled: enabled ?? this.enabled,
    quietHours: quietHours ?? this.quietHours,
    showDetails: showDetails ?? this.showDetails,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
  );
}

String reminderDuration(int minutes) => minutes % 1440 == 0
    ? '${minutes ~/ 1440} day${minutes == 1440 ? '' : 's'}'
    : minutes % 60 == 0
    ? '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}'
    : '$minutes minutes';
