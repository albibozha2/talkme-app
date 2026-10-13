// The payment page (POK / PayPal) shown inside the app on phones; browsers use a new tab instead.
export 'pay_webview_stub.dart' if (dart.library.io) 'pay_webview_native.dart';
