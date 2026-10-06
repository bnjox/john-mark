import '../../core/models.dart';
import '../bible/bible_repository.dart';
import '../semantic/semantic_retriever.dart';
import 'reference_parser.dart';

class ScriptureMatcher {
  ScriptureMatcher({
    required this.repository,
    required this.displayTranslation,
    required this.semanticRetriever,
  });

  static const _alternativeSemanticThreshold = 0.75;
  static const _semanticThreshold = 0.82;
  static const _highConfidenceThreshold = 0.88;

  final BibleRepository repository;
  final Translation displayTranslation;
  final SemanticRetriever semanticRetriever;
  final ReferenceParser _referenceParser = const ReferenceParser();

  Future<MatchUpdate?> match(String finalizedText) async {
    final latestText = finalizedText
        .split('\n')
        .lastWhere((segment) => segment.trim().isNotEmpty, orElse: () => '');
    final reference = _referenceParser.parse(latestText);
    if (reference != null) {
      final passage = await repository.passage(
        displayTranslation.id,
        reference,
      );
      if (passage != null) {
        return MatchUpdate(
          featured: MatchCandidate(
            passage: passage,
            score: 1,
            band: ConfidenceBand.high,
          ),
        );
      }
    }

    if (semanticRetriever.status != SemanticStatus.ready) return null;
    final hits = await semanticRetriever.search(finalizedText, limit: 8);
    final strongest = <ScriptureReference, SemanticHit>{};
    for (final hit in hits) {
      if (hit.score < _alternativeSemanticThreshold) continue;
      final current = strongest[hit.reference];
      if (current == null || hit.score > current.score) {
        strongest[hit.reference] = hit;
      }
    }
    final ranked = strongest.values.toList(growable: false)
      ..sort(_compareSemanticHits);
    if (ranked.isEmpty || ranked.first.score < _semanticThreshold) return null;
    final candidates = <MatchCandidate>[];
    for (final hit in ranked) {
      final passage = await repository.passage(
        displayTranslation.id,
        hit.reference,
      );
      if (passage == null) continue;
      candidates.add(
        MatchCandidate(
          passage: passage,
          score: hit.score,
          band: hit.score >= _highConfidenceThreshold
              ? ConfidenceBand.high
              : ConfidenceBand.possible,
        ),
      );
      if (candidates.length == 4) break;
    }
    if (candidates.isEmpty) return null;
    return MatchUpdate(
      featured: candidates.first,
      alternatives: List.unmodifiable(candidates.skip(1)),
    );
  }
}

int _compareSemanticHits(SemanticHit left, SemanticHit right) {
  final score = right.score.compareTo(left.score);
  if (score != 0) return score;
  for (final comparison in [
    left.reference.book.compareTo(right.reference.book),
    left.reference.chapter.compareTo(right.reference.chapter),
    left.reference.startVerse.compareTo(right.reference.startVerse),
    left.reference.endVerse.compareTo(right.reference.endVerse),
    left.translationId.compareTo(right.translationId),
  ]) {
    if (comparison != 0) return comparison;
  }
  return 0;
}
