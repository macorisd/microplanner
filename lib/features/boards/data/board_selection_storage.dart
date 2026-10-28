import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../core/data/private_storage.dart';

abstract interface class BoardSelectionStorage {
  Future<String?> read(String ownerId);
  Future<void> write(String ownerId, String boardId);
}

/// Device-local preferences are separate from cloud workspace content.
class PrivateBoardSelectionStorage implements BoardSelectionStorage {
  final PrivateStorage storage;
  const PrivateBoardSelectionStorage(this.storage);
  String _key(String ownerId) =>
      'last_board_${sha256.convert(utf8.encode(ownerId))}';
  @override
  Future<String?> read(String ownerId) => storage.read(_key(ownerId));
  @override
  Future<void> write(String ownerId, String boardId) =>
      storage.write(_key(ownerId), boardId);
}
