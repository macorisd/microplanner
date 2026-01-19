import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'features/auth/data/auth_service.dart';
import 'features/boards/data/models/board.dart';
import 'features/boards/data/models/subject.dart';
import 'features/boards/providers/boards_provider.dart';
import 'features/tasks/data/models/task.dart';
import 'features/tasks/providers/tasks_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  
  // Register Hive adapters
  Hive.registerAdapter(TaskAdapter());
  Hive.registerAdapter(BoardAdapter());
  Hive.registerAdapter(SubjectAdapter());

  // Create providers
  final authService = AuthService();
  final boardsProvider = BoardsProvider();
  final tasksProvider = TasksProvider();

  // Initialize providers (loads from Hive)
  await boardsProvider.init();
  await tasksProvider.init(boardsProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: boardsProvider),
        ChangeNotifierProvider.value(value: tasksProvider),
      ],
      child: const MicroPlannerApp(),
    ),
  );
}
