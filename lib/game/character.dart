/// Shared character identity used by settings, the game painter, matchmaking
/// and the database. Lives outside `ui/` so services and game code can use it
/// without importing widgets.
class Character {
  /// Every selectable character. Both artwork sheets hold two full-figure
  /// cells (female first, male second); the `_round` ids are the round-palm
  /// variants, so they share the base body sprite.
  static const List<({String id, String label})> all = [
    (id: 'male', label: 'Male'),
    (id: 'female', label: 'Female'),
    (id: 'male_round', label: 'Round male'),
    (id: 'female_round', label: 'Round female'),
  ];

  static const String fallback = 'male';

  static bool isKnown(String character) => all.any((c) => c.id == character);

  /// Normalizes a value that may come from settings or the network. An
  /// unknown id falls back to the default so a bad value can never blank a
  /// sprite or crash the painter.
  static String normalize(String? character) =>
      character != null && isKnown(character) ? character : fallback;

  static bool isFemale(String? character) =>
      normalize(character).startsWith('female');

  /// Round-palm variants only change hand size in the body painter.
  static bool isRound(String? character) => normalize(character).endsWith('_round');
}
