import 'dart:js_interop';
@JS('window.sessionStorage.getItem')
external JSString? _getItem(JSString key);
@JS('window.sessionStorage.setItem')
external void _setItem(JSString key, JSString value);
@JS('window.sessionStorage.removeItem')
external void _removeItem(JSString key);
String? readSession(String key) => _getItem(key.toJS)?.toDart;
void writeSession(String key, String value) => _setItem(key.toJS, value.toJS);
void clearSession(String key) => _removeItem(key.toJS);
