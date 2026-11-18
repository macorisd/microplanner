import 'dart:convert';

import 'api_client.dart';
import 'private_storage.dart';

const accountDeletionJournal = 'account-deletion';
const _accountStatuses = 'account-status-keys';

Future<Map<String, String>> readAccountStatusKeys(
  PrivateStorage storage,
) async {
  final raw = await storage.read(_accountStatuses);
  return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
}

Future<void> writeAccountStatusKeys(
  PrivateStorage storage,
  Map<String, String> keys,
) => keys.isEmpty
    ? storage.delete(_accountStatuses)
    : storage.write(_accountStatuses, jsonEncode(keys));

Future<bool> accountWasDeleted(ApiClient api, String owner, String key) async {
  final result = await api.request(
    'POST',
    '/account/deletion/status',
    body: {'ownerId': owner, 'key': key},
  );
  return switch (result['status']) {
    'active' => false,
    'deleted' => true,
    _ => throw const ApiException(
      503,
      'invalid_response',
      'Invalid account status.',
    ),
  };
}

class AccountDeletion {
  const AccountDeletion(this.owner, {this.key, this.grant});

  final String owner;
  final String? key;
  final String? grant;
  bool get confirmed => grant == null;

  static AccountDeletion? decode(String? raw) {
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AccountDeletion(
      json['owner'] as String,
      key: json['key'] as String?,
      grant: json['grant'] as String?,
    );
  }

  String encode() => jsonEncode({'owner': owner, 'key': key, 'grant': grant});
}
