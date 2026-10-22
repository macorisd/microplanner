import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PrivateStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecurePrivateStorage implements PrivateStorage {
  final FlutterSecureStorage storage;
  const SecurePrivateStorage([this.storage = const FlutterSecureStorage()]);
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}
