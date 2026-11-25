/// Small key/value store that survives page reloads (browser localStorage).
abstract class LocalStore {
  String? read(String key);

  /// Returns false if the value could not be stored (e.g. quota exceeded).
  bool write(String key, String value);

  void remove(String key);

  /// Calls [callback] when the page is being closed or reloaded.
  void onPageHide(void Function() callback);
}
