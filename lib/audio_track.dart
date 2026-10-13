// A music player without a picture: the browser's own audio element on the web
// (Flutter's video player never loads a hidden one there), the video player on phones.
export 'audio_track_native.dart'
    if (dart.library.js_interop) 'audio_track_web.dart';
