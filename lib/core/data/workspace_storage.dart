import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../features/boards/data/models/board.dart';
import '../../features/boards/data/models/subject.dart';
import '../../features/tasks/data/models/task.dart';
import 'private_storage.dart';
import 'workspace_snapshot.dart';

abstract interface class WorkspaceCache {
  Future<WorkspaceSnapshot?> read(String ownerId);
  Future<void> write(String ownerId, WorkspaceSnapshot data);
}

/// Pending commands and recovery drafts live alongside the encrypted cache.
abstract interface class WorkspaceJournal {
  Future<String?> readJournal(String ownerId);
  Future<void> writeJournal(String ownerId, String value);
}

/// Last observation time of the cached workspace, stored per account.
abstract interface class WorkspaceHistory {
  Future<DateTime?> readSeenAt(String ownerId);
  Future<void> markSeenAt(String ownerId, DateTime time);
}

class EncryptedWorkspaceCache
    implements WorkspaceCache, WorkspaceJournal, WorkspaceHistory {
  final PrivateStorage storage;
  final Map<String, Future<Box<String>>> _boxes = {};
  final Map<String, Future<void>> _journalWrites = {};
  EncryptedWorkspaceCache(this.storage);
  Future<Box<String>> _box(String ownerId) =>
      _boxes.putIfAbsent(ownerId, () async {
        final suffix = sha256.convert(utf8.encode(ownerId)).toString();
        final keyName = 'cache_key_$suffix';
        var key = await storage.read(keyName);
        if (key == null) {
          key = base64Encode(Hive.generateSecureKey());
          await storage.write(keyName, key);
        }
        return Hive.openBox<String>(
          'cloud_cache_$suffix',
          encryptionCipher: HiveAesCipher(base64Decode(key)),
        );
      });
  @override
  Future<WorkspaceSnapshot?> read(String ownerId) async {
    final value = (await _box(ownerId)).get('snapshot');
    return value == null
        ? null
        : WorkspaceSnapshot.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> write(String ownerId, WorkspaceSnapshot data) async =>
      (await _box(ownerId)).putAll({
        'snapshot': jsonEncode(data.toJson()),
        'seenAt': DateTime.now().toUtc().toIso8601String(),
      });

  @override
  Future<DateTime?> readSeenAt(String ownerId) async {
    final raw = (await _box(ownerId)).get('seenAt');
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  @override
  Future<void> markSeenAt(String ownerId, DateTime time) async =>
      (await _box(ownerId)).put('seenAt', time.toUtc().toIso8601String());

  @override
  Future<String?> readJournal(String ownerId) async {
    await _journalWrites[ownerId];
    return (await _box(ownerId)).get('journal');
  }

  @override
  Future<void> writeJournal(String ownerId, String value) {
    final previous = _journalWrites[ownerId] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) async {
      await (await _box(ownerId)).put('journal', value);
    });
    _journalWrites[ownerId] = next;
    return next;
  }
}

abstract interface class LegacyWorkspace {
  Future<bool> available(String ownerId);
  Future<String> get sourceId;
  Future<WorkspaceSnapshot> read();
  Future<void> imported(String ownerId);
  Future<void> dismiss(String ownerId);
}

class HiveLegacyWorkspace implements LegacyWorkspace {
  Future<Box<String>> get _meta => Hive.openBox<String>('cloud_migration');
  @override
  Future<String> get sourceId async {
    final meta = await _meta;
    var value = meta.get('sourceId');
    if (value == null) {
      value = const Uuid().v4();
      await meta.put('sourceId', value);
    }
    return value;
  }

  @override
  Future<bool> available(String ownerId) async {
    final meta = await _meta;
    if (meta.get('importedBy') != null ||
        meta.get('dismissed_$ownerId') != null) {
      return false;
    }
    for (final name in ['boards', 'subjects', 'tasks']) {
      if (await Hive.boxExists(name)) {
        // Open with its original adapter and do not modify legacy records.
        final count = switch (name) {
          'boards' => (await Hive.openBox<Board>(name)).length,
          'subjects' => (await Hive.openBox<Subject>(name)).length,
          _ => (await Hive.openBox<Task>(name)).length,
        };
        if (count > 0) return true;
      }
    }
    return false;
  }

  @override
  Future<WorkspaceSnapshot> read() async {
    final boards = await Hive.boxExists('boards')
        ? (await Hive.openBox<Board>('boards')).values.toList()
        : <Board>[];
    final subjects = await Hive.boxExists('subjects')
        ? (await Hive.openBox<Subject>('subjects')).values.toList()
        : <Subject>[];
    final tasks = await Hive.boxExists('tasks')
        ? (await Hive.openBox<Task>('tasks')).values.toList()
        : <Task>[];
    // Repair relationships in the payload only. Original Hive objects stay intact.
    final needsDefault =
        boards.isEmpty ||
        tasks.any(
          (t) => t.boardId == null || !boards.any((b) => b.id == t.boardId),
        );
    final normalizedBoards = [...boards];
    if (needsDefault && !boards.any((b) => b.id == 'default-board')) {
      normalizedBoards.add(
        Board.create(id: 'default-board', name: 'Imported tasks'),
      );
    }
    final normalizedSubjects = subjects
        .where((s) => normalizedBoards.any((b) => b.id == s.boardId))
        .toList();
    final normalizedTasks = tasks.map((t) {
      final boardId = normalizedBoards.any((b) => b.id == t.boardId)
          ? t.boardId!
          : 'default-board';
      final legacyId = t.subjectId ?? (t.subject.isEmpty ? null : t.subject);
      final subjectId =
          normalizedSubjects.any(
            (s) => s.id == legacyId && s.boardId == boardId,
          )
          ? legacyId
          : null;
      return t.copyWith(boardId: boardId, subjectId: subjectId);
    }).toList();
    return WorkspaceSnapshot(
      boards: normalizedBoards,
      subjects: normalizedSubjects,
      tasks: normalizedTasks,
    ).clone();
  }

  @override
  Future<void> imported(String ownerId) async =>
      (await _meta).put('importedBy', ownerId);
  @override
  Future<void> dismiss(String ownerId) async =>
      (await _meta).put('dismissed_$ownerId', 'yes');
}
