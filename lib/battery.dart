// The battery of this phone (or computer, in Chrome/Edge). Read only on the device;
// it is sent to TalkMe only inside diagnostics reports, and only when the person turned them on.
export 'battery_native.dart' if (dart.library.js_interop) 'battery_web.dart';
