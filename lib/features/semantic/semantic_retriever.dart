import '../../core/models.dart';

enum SemanticStatus { initializing, ready, unavailable }

class SemanticAssetMetadata {
  const SemanticAssetMetadata({
    required this.modelId,
    required this.modelRevision,
    required this.bibleFingerprint,
    required this.translations,
    required this.quantization,
    required this.createdByVersion,
  });

  final String modelId;
  final String modelRevision;
  final String bibleFingerprint;
  final List<String> translations;
  final String quantization;
  final String createdByVersion;
}

class SemanticHit {
  const SemanticHit({
    required this.reference,
    required this.translationId,
    required this.score,
  });

  final ScriptureReference reference;
  final String translationId;
  final double score;
}

abstract interface class SemanticRetriever {
  SemanticStatus get status;

  Future<List<SemanticHit>> search(String text, {int limit = 8});
}

abstract interface class SemanticVectorIndex {
  Future<List<SemanticHit>> search(List<double> query, {int limit = 8});

  Future<void> dispose();
}
