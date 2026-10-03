import '../../core/models.dart';
import '../bible/bible_repository.dart';
import 'detection_evidence.dart';
import 'match_stabilizer.dart';
import 'normalizer.dart';
import 'quote_matcher.dart';

class LexicalEvidenceMatcher {
  LexicalEvidenceMatcher(
    this._repository, {
    this.possibleThreshold = 0.68,
    this.replacementMargin = MatchConfig.defaultReplacementMargin,
  });

  final BibleRepository _repository;
  final double possibleThreshold;
  final double replacementMargin;

  Future<List<DetectionEvidence>> match(String text) async {
    final query = significantTokens(
      text,
      limit: QuoteMatcher.maxSignificantTokens,
    );
    if (query.length < 4) return const [];
    final passages = await _repository.quoteCandidatesAcrossTranslations(
      query,
      limitPerTranslation: QuoteMatcher.maxCandidates,
    );

    final strongestByReference = <ScriptureReference, DetectionEvidence>{};
    for (final sourced in passages) {
      final candidateTokens = significantTokens(sourced.passage.text);
      if (candidateTokens.length < 4) continue;
      final score = lexicalMatchScore(query, candidateTokens);
      if (score < possibleThreshold) continue;
      final evidence = DetectionEvidence(
        reference: sourced.passage.reference,
        score: score,
        kind: EvidenceKind.lexical,
        sourceTranslationId: sourced.translationId,
      );
      final existing = strongestByReference[evidence.reference];
      if (existing == null || _compare(evidence, existing) < 0) {
        strongestByReference[evidence.reference] = evidence;
      }
    }

    final matches = strongestByReference.values.toList(growable: false)
      ..sort(_compare);
    if (_hasMateriallyTiedNonOverlappingLeaders(matches)) return const [];
    return matches;
  }

  bool _hasMateriallyTiedNonOverlappingLeaders(
    List<DetectionEvidence> matches,
  ) {
    if (matches.length < 2) return false;
    final best = matches.first;
    for (final candidate in matches.skip(1)) {
      if (best.score - candidate.score > replacementMargin) break;
      if (!_overlaps(best.reference, candidate.reference)) return true;
    }
    return false;
  }
}

int _compare(DetectionEvidence left, DetectionEvidence right) {
  final score = right.score.compareTo(left.score);
  if (score != 0) return score;
  final reference = _compareReferences(left.reference, right.reference);
  if (reference != 0) return reference;
  return (left.sourceTranslationId ?? '').compareTo(
    right.sourceTranslationId ?? '',
  );
}

int _compareReferences(ScriptureReference left, ScriptureReference right) {
  for (final comparison in [
    left.book.compareTo(right.book),
    left.chapter.compareTo(right.chapter),
    left.startVerse.compareTo(right.startVerse),
    left.endVerse.compareTo(right.endVerse),
  ]) {
    if (comparison != 0) return comparison;
  }
  return 0;
}

bool _overlaps(ScriptureReference left, ScriptureReference right) =>
    left.book == right.book &&
    left.chapter == right.chapter &&
    left.startVerse <= right.endVerse &&
    right.startVerse <= left.endVerse;
