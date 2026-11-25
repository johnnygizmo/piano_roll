import 'local_store.dart';

/// In-memory store used on non-web targets and in tests.
class _MemoryStore implements LocalStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  bool write(String key, String value) {
    _values[key] = value;
    return true;
  }

  @override
  void remove(String key) => _values.remove(key);

  @override
  void onPageHide(void Function() callback) {}
}

LocalStore createLocalStoreImpl() => _MemoryStore();
