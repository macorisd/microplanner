import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/data/models/subject.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'support/fakes.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('microplanner-test-');
    Hive.init(temporary.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(TaskAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(BoardAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SubjectAdapter());
  });
  tearDown(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });
  test(
    'encrypted cache uses distinct keys and boxes per user and survives reopening',
    () async {
      final secure = MemoryPrivateStorage();
      final cache = EncryptedWorkspaceCache(secure);
      await cache.write('A', snapshot('A secret'));
      await cache.write('B', snapshot('B secret'));
      expect(secure.values.length, 2);
      expect(secure.values.values.toSet().length, 2);
      await Hive.close();
      final reopened = EncryptedWorkspaceCache(secure);
      expect((await reopened.read('A'))!.boards.single.name, 'A secret');
      expect((await reopened.read('B'))!.boards.single.name, 'B secret');
      await Hive.close();
      for (final file in temporary.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.hive'),
      )) {
        expect(
          String.fromCharCodes(await file.readAsBytes()),
          isNot(contains('A secret')),
        );
      }
    },
  );
  test(
    'pending journal is encrypted, account isolated and survives reopening',
    () async {
      final secure = MemoryPrivateStorage();
      final cache = EncryptedWorkspaceCache(secure);
      await cache.writeJournal('A', 'A pending private draft');
      await cache.writeJournal('B', 'B pending private draft');
      await Hive.close();
      final reopened = EncryptedWorkspaceCache(secure);
      expect(await reopened.readJournal('A'), 'A pending private draft');
      expect(await reopened.readJournal('B'), 'B pending private draft');
      await Hive.close();
      for (final file in temporary.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.hive'),
      )) {
        expect(
          String.fromCharCodes(await file.readAsBytes()),
          isNot(contains('pending private draft')),
        );
      }
    },
  );
  test(
    'cached observation time survives restart and stays account scoped',
    () async {
      final secure = MemoryPrivateStorage();
      final cache = EncryptedWorkspaceCache(secure);
      await cache.write('A', snapshot('A'));
      await cache.write('B', snapshot('B'));
      final seen = DateTime.utc(2030, 1, 1);
      await cache.markSeenAt('A', seen);
      await Hive.close();
      final reopened = EncryptedWorkspaceCache(secure);
      expect((await reopened.readSeenAt('A'))!.toUtc(), seen);
      expect((await reopened.readSeenAt('B'))!.toUtc(), isNot(seen));
    },
  );
  test(
    'legacy normalization repairs old relations without changing original Hive data',
    () async {
      final tasks = await Hive.openBox<Task>('tasks');
      await tasks.put(
        'old',
        Task(
          id: 'old',
          name: 'Legacy',
          deadline: DateTime(2026, 11),
          createdAt: DateTime(2026, 10),
          typeIndex: 0,
          priorityIndex: 1,
          subject: 'orphan-subject',
        ),
      );
      final legacy = HiveLegacyWorkspace();
      expect(await legacy.available('A'), isTrue);
      final source = await legacy.sourceId;
      expect(await legacy.sourceId, source);
      final migrated = await legacy.read();
      expect(migrated.tasks.single.boardId, 'default-board');
      expect(migrated.tasks.single.subjectId, isNull);
      expect(tasks.get('old')!.boardId, isNull);
      await legacy.imported('A');
      expect(await legacy.available('B'), isFalse);
      expect(tasks.length, 1); // Keep the original backup.
    },
  );
}
