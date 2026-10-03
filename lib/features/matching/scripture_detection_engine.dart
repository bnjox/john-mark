import '../../core/models.dart';
import '../bible/bible_repository.dart';
import '../semantic/semantic_retriever.dart';
import 'detection_evidence.dart';
import 'lexical_evidence_matcher.dart';
import 'match_stabilizer.dart';
import 'reference_parser.dart';

class ScriptureDetectionEngine {
  ScriptureDetectionEngine({
    required BibleRepository repository,
    required List<Translation> translations,
    required this.displayTranslation,
    required this._semanticRetriever,
    this.config = const MatchConfig(),
  }) : _repository = repository,
       _translations = List.unmodifiable(translations),
       _referenceParser = ReferenceParser(repository),
       _lexicalMatcher = LexicalEvidenceMatcher(
         repository,
         possibleThreshold: config.possibleThreshold,
         replacementMargin: config.replacementMargin,
       ),
       _stabilizer = MatchStabilizer(config);

  final BibleRepository _repository;
  final List<Translation> _translations;
  final SemanticRetriever _semanticRetriever;
  final ReferenceParser _referenceParser;
  final LexicalEvidenceMatcher _lexicalMatcher;
  final MatchStabilizer _stabilizer;
  final Translation displayTranslation;
  final MatchConfig config;
  ScriptureReference? _pendingSemanticReference;
  int _pendingSemanticWindows = 0;

  MatchUpdate get current => _stabilizer.current;

  void reset() {
    _stabilizer.reset();
    _clearSemanticSupport();
  }

  Future<MatchUpdate?> match(String finalizedText) async {
    final explicit = await _referenceParser.parseAny(
      finalizedText,
      _translations,
    );
    if (explicit != null) {
      _clearSemanticSupport();
      return _stabilizer.update(await _resolve([explicit]));
    }

    final lexical = await _lexicalMatcher.match(finalizedText);
    if (lexical.isNotEmpty && lexical.first.score >= config.strongThreshold) {
      _clearSemanticSupport();
      return _stabilizer.update(await _resolve(lexical));
    }

    final semantic = await _semanticEvidence(finalizedText);
    if (semantic.isNotEmpty) {
      return _stabilizer.update(await _resolve(semantic));
    }
    return _stabilizer.update(await _resolve(lexical));
  }

  Future<List<DetectionEvidence>> _semanticEvidence(String text) async {
    if (_semanticRetriever.status != SemanticStatus.ready) {
      _clearSemanticSupport();
      return const [];
    }
    final hits = await _semanticRetriever.search(text, limit: 8);
    final strongest = <ScriptureReference, SemanticHit>{};
    for (final hit in hits) {
      final current = strongest[hit.reference];
      if (current == null || hit.score > current.score) {
        strongest[hit.reference] = hit;
      }
    }
    final ranked = strongest.values.toList(growable: false)
      ..sort(_compareSemanticHits);
    if (ranked.isEmpty || ranked.first.score < config.semanticThreshold) {
      _clearSemanticSupport();
      return const [];
    }
    if (ranked.length > 1 &&
        ranked.first.score - ranked[1].score < config.semanticWinnerMargin) {
      _clearSemanticSupport();
      return const [];
    }

    final winner = ranked.first.reference;
    if (_pendingSemanticReference == winner) {
      _pendingSemanticWindows++;
    } else {
      _pendingSemanticReference = winner;
      _pendingSemanticWindows = 1;
    }
    if (_pendingSemanticWindows < config.semanticConfirmationWindows) {
      return const [];
    }
    _clearSemanticSupport();
    return ranked
        .where((hit) => hit.score >= config.semanticThreshold)
        .map(
          (hit) => DetectionEvidence(
            reference: hit.reference,
            score: hit.score,
            kind: EvidenceKind.semantic,
            sourceTranslationId: hit.translationId,
          ),
        )
        .toList(growable: false);
  }

  Future<List<MatchCandidate>> _resolve(
    List<DetectionEvidence> evidence,
  ) async {
    final candidates = <MatchCandidate>[];
    for (final item in evidence) {
      final passage = await _repository.passage(
        displayTranslation.id,
        item.reference,
      );
      if (passage == null) continue;
      candidates.add(
        MatchCandidate(
          passage: passage,
          score: item.score,
          band: item.score >= config.strongThreshold
              ? ConfidenceBand.high
              : ConfidenceBand.possible,
          explicitReference: item.kind == EvidenceKind.explicitReference,
        ),
      );
      if (candidates.length == 4) break;
    }
    return candidates;
  }

  void _clearSemanticSupport() {
    _pendingSemanticReference = null;
    _pendingSemanticWindows = 0;
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
