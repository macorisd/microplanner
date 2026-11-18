import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/notifications/notification_controller.dart';
import 'core/notifications/notification_adapter.dart';
import 'core/notifications/background_sync.dart';
import 'core/constants/app_config.dart';
import 'core/data/api_client.dart';
import 'core/data/private_storage.dart';
import 'core/data/workspace_controller.dart';
import 'core/data/workspace_storage.dart';
import 'core/widgets/app_bootstrap.dart';
import 'features/auth/data/auth_service.dart';
import 'features/boards/data/models/board.dart';
import 'features/boards/data/models/subject.dart';
import 'features/boards/providers/boards_provider.dart';
import 'features/boards/data/board_selection_storage.dart';
import 'features/boards/data/board_column_storage.dart';
import 'features/tasks/data/models/task.dart';
import 'features/tasks/providers/tasks_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppBootstrap(initialize: _initializeApplication));
}

@pragma('vm:entry-point')
Future<void> backgroundReminderSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runBackgroundReminderSync();
}

Future<Widget> _initializeApplication() async {
  final background = BackgroundSyncBridge();
  await background.startForeground();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(TaskAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(BoardAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SubjectAdapter());
  final api = ApiClient(AppConfig.apiUrl);
  const storage = SecurePrivateStorage();
  final cache = EncryptedWorkspaceCache(storage);
  final legacy = HiveLegacyWorkspace();
  const selection = PrivateBoardSelectionStorage(storage);
  const columns = PrivateBoardColumnStorage(storage);
  late final BoardsProvider boards;
  late final NotificationController notifications;
  final auth = AuthService(
    api: api,
    storage: storage,
    purgeAccount: (owner) async {
      await notifications.eraseAccount(owner);
      await boards.drainPreferences(owner);
      await selection.erase(owner);
      await columns.erase(owner);
      await legacy.erase(owner);
      await cache.erase(owner);
    },
  );
  final workspace = WorkspaceController(
    auth: auth,
    api: api,
    cache: cache,
    legacy: legacy,
  );
  boards = BoardsProvider(
    workspace,
    selectionStorage: selection,
    columnStorage: defaultTargetPlatform == TargetPlatform.android
        ? columns
        : null,
  );
  final tasks = TasksProvider(workspace, boards);
  notifications = NotificationController(
    workspace: workspace,
    storage: storage,
    adapter: NativeNotificationAdapter(),
    background: background,
  );
  unawaited(auth.initialize());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: workspace),
      ChangeNotifierProvider.value(value: boards),
      ChangeNotifierProvider.value(value: tasks),
      ChangeNotifierProvider.value(value: notifications),
    ],
    child: const PlannerApp(),
  );
}
