import '../../core/models.dart';
import '../bible/bible_repository.dart';
import '../bible/display_translation_resolver.dart';
import 'book_aliases.dart';
import 'detection_evidence.dart';
import 'normalizer.dart';

class ReferenceParser {
  ReferenceParser(this._repository);

  final BibleRepository _repository;

  Future<DetectionEvidence?> parseAny(
    String text,
    List<Translation> translations,
  ) async {
    if (translations.isEmpty) return null;
    final display = resolveDisplayTranslation(translations);
    final ordered = [
      display,
      ...translations.where((translation) => translation.id != display.id),
    ];
    final reference = _extract(text);
    if (reference == null) return null;
    for (final translation in ordered) {
      if (await _repository.passage(translation.id, reference) != null) {
        return DetectionEvidence(
          reference: reference,
          score: 1,
          kind: EvidenceKind.explicitReference,
          sourceTranslationId: translation.id,
        );
      }
    }
    return null;
  }

  Future<MatchCandidate?> parse(String text, String translationId) async {
    final reference = _extract(text);
    if (reference == null) return null;
    final passage = await _repository.passage(translationId, reference);
    if (passage == null) return null;
    return MatchCandidate(
      passage: passage,
      score: 1,
      band: ConfidenceBand.high,
      explicitReference: true,
    );
  }

  ScriptureReference? _extract(String text) {
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
        return reference;
      }
    }
    return null;
  }
}
