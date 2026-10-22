import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:microplanner/core/data/api_client.dart';
import 'package:microplanner/core/data/private_storage.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/auth/data/google_authenticator.dart';
import 'package:microplanner/features/boards/data/models/board.dart';

Map<String, dynamic> session(String owner, {DateTime? expires}) => {
  'token': 'token-$owner',
  'expiresAt': (expires ?? DateTime.now().add(const Duration(days: 1)))
      .toUtc()
      .toIso8601String(),
  'user': {
    'id': owner,
    'email': '$owner@example.com',
    'displayName': owner,
    'photoUrl': null,
  },
};
WorkspaceSnapshot snapshot(String name, {int revision = 0}) =>
    WorkspaceSnapshot(
      revision: revision,
      boards: [
        Board(
          id: 'default-board',
          name: name,
          createdAt: DateTime(2026, 10, 22),
        ),
      ],
    );
http.Response jsonResponse(Object body, [int code = 200]) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json'},
);
Future<void> settleAsync() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class MemoryPrivateStorage implements PrivateStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeGoogle implements GoogleAuthenticator {
  String owner = 'A';
  Completer<Map<String, dynamic>?>? pending;
  @override
  Future<Map<String, dynamic>?> signIn(ApiClient api) async =>
      pending == null ? session(owner) : pending!.future;
  @override
  Future<void> signOut() async {}
  @override
  void cancel() {}
}

class MemoryCache implements WorkspaceCache {
  final Map<String, WorkspaceSnapshot> values = {};
  @override
  Future<WorkspaceSnapshot?> read(String ownerId) async =>
      values[ownerId]?.clone();
  @override
  Future<void> write(String ownerId, WorkspaceSnapshot data) async {
    values[ownerId] = data.clone();
  }
}

class FakeLegacy implements LegacyWorkspace {
  String? importedBy;
  bool exists = false;
  @override
  Future<bool> available(String ownerId) async => exists && importedBy == null;
  @override
  Future<String> get sourceId async => 'd6165e1c-2fe0-45d8-8898-8a7ff2db4d5a';
  @override
  Future<WorkspaceSnapshot> read() async => snapshot('Legacy');
  @override
  Future<void> imported(String ownerId) async {
    importedBy = ownerId;
  }

  @override
  Future<void> dismiss(String ownerId) async {
    exists = false;
  }
}

class FakeServer {
  final states = <String, WorkspaceSnapshot>{
    'A': snapshot('A private'),
    'B': snapshot('B private'),
  };
  bool offline = false;
  bool rejectSession = false;
  bool conflict = false;
  int writes = 0;
  Completer<http.Response>? nextRead;
  Completer<http.Response>? nextWrite;
  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final owner = (request.headers['authorization'] ?? '').replaceFirst(
      'Bearer token-',
      '',
    );
    if (request.url.path == '/auth/logout') {
      return jsonResponse({'status': 'signed_out'});
    }
    if (rejectSession) {
      return jsonResponse({'code': 'unauthorized', 'message': 'Expired'}, 401);
    }
    if (request.url.path == '/auth/me') {
      return jsonResponse({'user': session(owner)['user']});
    }
    if (request.method == 'GET') {
      final blocked = nextRead;
      nextRead = null;
      return blocked == null
          ? jsonResponse(states[owner]!.toJson())
          : blocked.future;
    }
    writes++;
    if (conflict) {
      conflict = false;
      return jsonResponse({
        'code': 'revision_conflict',
        'message': 'Another device changed your data.',
      }, 409);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final next = WorkspaceSnapshot.fromJson({
      ...body['data'] as Map<String, dynamic>,
      'revision': (body['revision'] as int) + 1,
    });
    states[owner] = next;
    final blocked = nextWrite;
    nextWrite = null;
    return blocked == null ? jsonResponse(next.toJson()) : blocked.future;
  }
}

class Harness {
  final server = FakeServer();
  final storage = MemoryPrivateStorage();
  final google = FakeGoogle();
  final cache = MemoryCache();
  final legacy = FakeLegacy();
  late final api = ApiClient(
    'http://localhost:3000',
    client: MockClient(server.handle),
  );
  late final auth = AuthService(api: api, storage: storage, google: google);
  late final workspace = WorkspaceController(
    auth: auth,
    api: api,
    cache: cache,
    legacy: legacy,
  );
  Future<void> initialize() async {
    workspace;
    await auth.initialize();
    await settleAsync();
  }

  Future<void> login(String owner) async {
    google.owner = owner;
    await auth.signInWithGoogle();
    await settleAsync();
  }

  void dispose() {
    workspace.dispose();
    auth.dispose();
  }
}
