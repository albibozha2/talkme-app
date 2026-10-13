// Google's own sign-in button (the browser requires it). Nothing on phones.
export 'google_button_stub.dart'
    if (dart.library.js_interop) 'google_button_web.dart';
