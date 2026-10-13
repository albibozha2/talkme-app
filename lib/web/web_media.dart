// Browser-only video helpers (cover pictures, preloading). Do nothing on phones.
export 'web_media_stub.dart' if (dart.library.js_interop) 'web_media_web.dart';
