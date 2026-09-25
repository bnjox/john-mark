import '../../core/models.dart';
import '../bible/bible_repository.dart';
import 'book_aliases.dart';
import 'normalizer.dart';

class ReferenceParser {
  ReferenceParser(this._repository);

  final BibleRepository _repository;

  Future<MatchCandidate?> parse(String text, String translationId) async {
    final normalized = normalizeSpokenText(text);
    if (normalized.isEmpty) return null;

    final aliases = bookAliases.keys.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final alias in aliases) {
      final expression = RegExp(
        '(?:^| )${RegExp.escape(alias)} '
        r'(?:(?:chapter) )?(\d{1,3}) '
        r'(?:(?:verse|verses) )?(\d{1,3})'
        r'(?: (?:through|to) (\d{1,3}))?(?= |$)',
      );
      for (final match in expression.allMatches(normalized)) {
        final chapter = int.parse(match.group(1)!);
        final startVerse = int.parse(match.group(2)!);
        final endVerse = int.tryParse(match.group(3) ?? '') ?? startVerse;
        if (chapter <= 0 || startVerse <= 0 || endVerse < startVerse) continue;

        final reference = ScriptureReference(
          book: bookAliases[alias]!,
          chapter: chapter,
          startVerse: startVerse,
          endVerse: endVerse,
        );
        final passage = await _repository.passage(translationId, reference);
        if (passage != null) {
          return MatchCandidate(
            passage: passage,
            score: 1,
            band: ConfidenceBand.high,
            explicitReference: true,
          );
        }
      }
    }
    return null;
  }
}
