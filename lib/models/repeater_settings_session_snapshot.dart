class RepeaterSettingsSessionSnapshot {
  final Map<String, String> valuesByKey;
  final Set<String> dirtyKeys;

  RepeaterSettingsSessionSnapshot({
    required Map<String, String> valuesByKey,
    Set<String> dirtyKeys = const {},
  }) : valuesByKey = Map.unmodifiable(valuesByKey),
       dirtyKeys = Set.unmodifiable(dirtyKeys);
}
