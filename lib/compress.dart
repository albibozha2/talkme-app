// Shrinks a video before it is uploaded (phones only; in the browser the file is sent as it is).
export 'compress_stub.dart' if (dart.library.io) 'compress_native.dart';
