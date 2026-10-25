import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/constants/app_config.dart';
import 'core/data/api_client.dart';
import 'core/data/private_storage.dart';
import 'core/data/workspace_controller.dart';
import 'core/data/workspace_storage.dart';
import 'features/auth/data/auth_service.dart';
import 'features/boards/data/models/board.dart';
import 'features/boards/data/models/subject.dart';
import 'features/boards/providers/boards_provider.dart';
import 'features/tasks/data/models/task.dart';
import 'features/tasks/providers/tasks_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await Hive.initFlutter();
  Hive.registerAdapter(TaskAdapter());
  Hive.registerAdapter(BoardAdapter());
  Hive.registerAdapter(SubjectAdapter());
  final api = ApiClient(AppConfig.apiUrl);
  const storage = SecurePrivateStorage();
  final auth = AuthService(api: api, storage: storage);
  final workspace = WorkspaceController(
    auth: auth,
    api: api,
    cache: EncryptedWorkspaceCache(storage),
    legacy: HiveLegacyWorkspace(),
  );
  final boards = BoardsProvider(workspace);
  final tasks = TasksProvider(workspace, boards);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: workspace),
        ChangeNotifierProvider.value(value: boards),
        ChangeNotifierProvider.value(value: tasks),
      ],
      child: const PlannerApp(),
    ),
  );
  unawaited(auth.initialize());
}
