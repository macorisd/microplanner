import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/testing.dart';
import 'package:microplanner/core/data/account_deletion.dart';
import 'package:microplanner/core/data/api_client.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/auth/data/google_authenticator.dart';
import 'package:microplanner/features/tasks/presentation/widgets/account_pages.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';

class _Google extends FakeGoogle implements AccountDeletionAuthenticator {
  int verifications = 0;

  @override
  Future<Map<String, dynamic>> verifyDeletion(
    ApiClient api,
    String token,
  ) async {
    verifications++;
    return {'grant': 'confirmed-grant'};
  }
}

void main() {
  test('lost response and interrupted cleanup survive restart', () async {
    final storage = MemoryPrivateStorage()
      ..values['session'] = jsonEncode({
        ...session('A'),
        'accountStatusKey': 'proof-A',
      });
    var deleted = false;
    var offline = false;
    var attempts = 0;
    var cleanups = 0;
    final api = ApiClient(
      'http://localhost',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/auth/me':
            return jsonResponse({'user': session('A')['user']});
          case '/account/deletion/status':
            expect(jsonDecode(request.body), {
              'ownerId': 'A',
              'key': 'proof-A',
            });
            if (offline) return jsonResponse({}, 503);
            return jsonResponse({'status': deleted ? 'deleted' : 'active'});
          case '/account/deletion/commit':
            expect(jsonDecode(request.body), {'grant': 'confirmed-grant'});
            attempts++;
            deleted = true;
            offline = true;
            return jsonResponse({}, 503);
          default:
            fail('Unexpected request: ${request.url.path}');
        }
      }),
    );
    final first = AuthService(
      api: api,
      storage: storage,
      purgeAccount: (_) async => fail('Unknown deletion cannot purge'),
    );
    await first.initialize();
    expect(await first.deleteAccount('A', 'confirmed-grant'), isFalse);
    expect(first.recoveringDeletion, isTrue);
    expect(storage.values[accountDeletionJournal], contains('confirmed-grant'));
    first.dispose();
    offline = false;
    final second = AuthService(
      api: api,
      storage: storage,
      purgeAccount: (owner) async {
        expect(owner, 'A');
        cleanups++;
        if (cleanups == 1) throw StateError('Interrupted cleanup');
      },
    );
    await second.initialize();
    expect(second.recoveringDeletion, isTrue);
    expect(storage.values['session'], isNull);
    expect(
      AccountDeletion.decode(storage.values[accountDeletionJournal])!.confirmed,
      isTrue,
    );
    offline = true;
    await second.retryDeletion();
    expect(second.recoveringDeletion, isFalse);
    expect(second.currentUser, isNull);
    expect(storage.values[accountDeletionJournal], isNull);
    expect(attempts, 1);
    expect(cleanups, 2);
    second.dispose();
  });

  test(
    'session expiry and a verified remote deletion have distinct local effects',
    () async {
      for (final deleted in [false, true]) {
        final storage = MemoryPrivateStorage()
          ..values['session'] = jsonEncode(session('A'));
        await writeAccountStatusKeys(storage, {'A': 'proof-A'});
        final purged = <String>[];
        final api = ApiClient(
          'http://localhost',
          client: MockClient((request) async {
            if (request.url.path == '/account/deletion/status') {
              return jsonResponse({'status': deleted ? 'deleted' : 'active'});
            }
            return jsonResponse({
              'code': 'unauthorized',
              'message': 'Expired',
            }, 401);
          }),
        );
        final auth = AuthService(
          api: api,
          storage: storage,
          purgeAccount: (owner) async {
            purged.add(owner);
          },
        );
        await auth.initialize();
        expect(auth.currentUser, isNull);
        expect(purged, deleted ? ['A'] : isEmpty);
        expect(storage.values[accountDeletionJournal], isNull);
        expect(
          (await readAccountStatusKeys(storage)).containsKey('A'),
          !deleted,
        );
        auth.dispose();
      }
    },
  );

  test(
    'a compatible signed-out device purges a deleted account on next start',
    () async {
      final storage = MemoryPrivateStorage();
      await writeAccountStatusKeys(storage, {
        'A': 'keep-key',
        'B': 'delete-key',
      });
      final purged = <String>[];
      final api = ApiClient(
        'http://localhost',
        client: MockClient((request) async {
          expect(request.url.path, '/account/deletion/status');
          final data = jsonDecode(request.body) as Map;
          return jsonResponse({
            'status': data['ownerId'] == 'A' ? 'active' : 'deleted',
          });
        }),
      );
      final auth = AuthService(
        api: api,
        storage: storage,
        purgeAccount: (owner) async => purged.add(owner),
      );
      await auth.initialize();
      expect(auth.currentUser, isNull);
      expect(purged, ['B']);
      expect(await readAccountStatusKeys(storage), {'A': 'keep-key'});
      auth.dispose();
    },
  );

  test(
    'purging an encrypted workspace removes its journal and key in isolation',
    () async {
      final location = await Directory.systemTemp.createTemp(
        'microplanner-erasure-',
      );
      Hive.init(location.path);
      addTearDown(() async {
        await Hive.close();
        await location.delete(recursive: true);
      });

      final storage = MemoryPrivateStorage();
      final cache = EncryptedWorkspaceCache(storage);
      await cache.write('A', snapshot('Delete'));
      await cache.write('B', snapshot('Keep'));
      final pending = cache.writeJournal('A', '{"operations":[]}');
      await cache.erase('A');
      await pending;
      await cache.erase('A');
      await expectLater(
        cache.write('A', snapshot('Late write')),
        throwsStateError,
      );
      expect((await cache.read('B'))!.boards.single.name, 'Keep');
      expect(
        storage.values.keys.where((key) => key.startsWith('cache_key_')),
        hasLength(1),
      );
      expect(storage.values['reminders-pending:A'], isNull);
      final reopened = EncryptedWorkspaceCache(storage);
      expect(await reopened.read('A'), isNull);
      expect(await reopened.readJournal('A'), isNull);
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets(
      '$platform Account requires Google and a separate confirmation',
      (tester) async {
        tester.view.physicalSize = platform == TargetPlatform.windows
            ? const Size(768, 456)
            : const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryPrivateStorage()
          ..values['session'] = jsonEncode({
            ...session('A'),
            'accountStatusKey': 'proof-A',
          });
        final server = FakeServer();
        final api = ApiClient(
          'http://localhost',
          client: MockClient(server.handle),
        );
        final google = _Google();
        final auth = AuthService(
          api: api,
          storage: store,
          google: google,
          purgeAccount: (_) async =>
              fail('Cancellation must preserve the account'),
        );
        final workspace = WorkspaceController(
          auth: auth,
          api: api,
          cache: MemoryCache(),
          legacy: FakeLegacy(),
        );
        await tester.runAsync(() async {
          await auth.initialize();
          await settleAsync();
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: workspace),
            ],
            child: MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(body: SettingsPage(onBack: () {})),
            ),
          ),
        );
        await tester.tap(find.text('Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete account'));
        await tester.pumpAndSettle();
        expect(find.text('Delete'), findsNothing);
        expect(find.textContaining('It cannot be undone.'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Verify with Google'), findsNothing);
        expect(google.verifications, 0);
        await tester.tap(find.text('Delete account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verify with Google'));
        await tester.pumpAndSettle();
        expect(google.verifications, 1);
        expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(auth.currentUser?.id, 'A');
        expect(store.values[accountDeletionJournal], isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        auth.dispose();
      },
    );
  }
}
