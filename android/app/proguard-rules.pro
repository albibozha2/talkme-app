# WebRTC / LiveKit use JNI and reflection; keep them intact in release builds.
-keep class org.webrtc.** { *; }
-keep class io.livekit.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
