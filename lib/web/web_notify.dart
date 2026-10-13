// Browser-only helpers (tab title, desktop pop-ups). Does nothing on phones.
export 'web_notify_stub.dart'
    if (dart.library.js_interop) 'web_notify_web.dart';
