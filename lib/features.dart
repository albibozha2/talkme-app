/// Parts of the app switched on / off in Admin → Features. Read from /config at start and refreshed when the
/// app comes back to the front. Unknown keys (older servers) count as on.
class Features {
  Features._();

  static Map<String, bool> _flags = const {};

  static bool on(String key) => _flags[key] ?? true;

  static void update(Map<String, bool> flags) => _flags = flags;
}
