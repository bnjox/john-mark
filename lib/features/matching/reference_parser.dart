import '../../core/models.dart';
import 'book_aliases.dart';
import 'normalizer.dart';

class ReferenceParser {
  const ReferenceParser();

  static final RegExp _referencePattern = _buildPattern();

  ScriptureReference? parse(String text) {
    final normalized = normalizeSpokenText(text);
    if (normalized.isEmpty) return null;

    ScriptureReference? latest;
    for (final match in _referencePattern.allMatches(normalized)) {
      final chapter = int.parse(match.group(2)!);
      final startVerse = int.parse(match.group(3)!);
      final endVerse = int.tryParse(match.group(4) ?? '') ?? startVerse;
      if (chapter <= 0 || startVerse <= 0 || endVerse < startVerse) continue;
      latest = ScriptureReference(
        book: bookAliases[match.group(1)!]!,
        chapter: chapter,
        startVerse: startVerse,
        endVerse: endVerse,
      );
    }
    return latest;
  }
}

RegExp _buildPattern() {
  final aliases = bookAliases.keys.toList()
    ..sort((left, right) => right.length.compareTo(left.length));
  return RegExp(
    '(?:^| )(${aliases.map(RegExp.escape).join('|')}) '
    r'(?:(?:chapter) )?(\d{1,3}) '
    r'(?:(?:verse|verses) )?(\d{1,3})'
    r'(?: (?:through|to) (\d{1,3}))?(?= |$)',
  );
}
