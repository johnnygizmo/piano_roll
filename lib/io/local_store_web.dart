import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'local_store.dart';

class _WebLocalStore implements LocalStore {
  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  bool write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void remove(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
  }

  @override
  void onPageHide(void Function() callback) {
    web.window.addEventListener('pagehide', ((web.Event _) => callback()).toJS);
  }
}

LocalStore createLocalStoreImpl() => _WebLocalStore();
