import '../../core/models.dart';

enum EvidenceKind { explicitReference, lexical, semantic }

class DetectionEvidence {
  const DetectionEvidence({
    required this.reference,
    required this.score,
    required this.kind,
    this.sourceTranslationId,
  });

  final ScriptureReference reference;
  final double score;
  final EvidenceKind kind;
  final String? sourceTranslationId;
}

class SourcedPassage {
  const SourcedPassage({required this.translationId, required this.passage});

  final String translationId;
  final Passage passage;
}
