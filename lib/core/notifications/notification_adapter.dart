import 'package:flutter/services.dart';

abstract interface class NotificationAdapter {
  Future<Map<String, dynamic>> status({bool request = false});
  Future<void> schedule(Map<String, dynamic> event);
  Future<void> cancel(int id);
  Future<List<String>> pending();
  Future<String?> launch();
  Future<void> settings({bool exact = false});
  set onActivated(void Function()? callback);
}

class NativeNotificationAdapter implements NotificationAdapter {
  static const channel = MethodChannel('microplanner/notifications');
  void Function()? _onActivated;
  NativeNotificationAdapter() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'activated') _onActivated?.call();
    });
  }
  @override
  set onActivated(void Function()? callback) => _onActivated = callback;
  @override
  Future<Map<String, dynamic>> status({bool request = false}) async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod(
              request ? 'requestPermission' : 'status',
            ) ??
            {},
      );
  @override
  Future<void> schedule(Map<String, dynamic> event) =>
      channel.invokeMethod('schedule', event);
  @override
  Future<void> cancel(int id) => channel.invokeMethod('cancel', id);
  @override
  Future<List<String>> pending() async =>
      (await channel.invokeListMethod<String>('pending')) ?? [];
  @override
  Future<String?> launch() => channel.invokeMethod<String>('launch');
  @override
  Future<void> settings({bool exact = false}) =>
      channel.invokeMethod(exact ? 'exactPermission' : 'settings');
}
