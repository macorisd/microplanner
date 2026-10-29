import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../core/data/private_storage.dart';

abstract interface class BoardColumnStorage {
  Future<Map<String, int>> read(String ownerId);
  Future<void> write(String ownerId, Map<String, int> columns);
}

/// Read all device-local column preferences once, keeping board switches instant.
class PrivateBoardColumnStorage implements BoardColumnStorage {
  final PrivateStorage storage;
  const PrivateBoardColumnStorage(this.storage);
  String _key(String owner) =>
      'board_columns_${sha256.convert(utf8.encode(owner))}';

  @override
  Future<Map<String, int>> read(String ownerId) async {
    final value = await storage.read(_key(ownerId));
    if (value == null) return {};
    if (value.length > 65536) {
      throw const FormatException('Invalid column preferences');
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Invalid column preferences');
    }
    return {
      for (final entry in decoded.entries)
        if (entry.key is String &&
            entry.value is int &&
            entry.value >= 0 &&
            entry.value <= 2)
          entry.key as String: entry.value as int,
    };
  }

  @override
  Future<void> write(String ownerId, Map<String, int> columns) =>
      storage.write(_key(ownerId), jsonEncode(columns));
}
