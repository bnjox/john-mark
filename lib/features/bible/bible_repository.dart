import '../../core/models.dart';
import '../matching/detection_evidence.dart';

export '../matching/detection_evidence.dart' show SourcedPassage;

abstract interface class BibleRepository {
  Future<List<Translation>> translations();

  Future<Passage?> passage(String translationId, ScriptureReference reference);

  Future<Passage?> context(
    String translationId,
    ScriptureReference reference, {
    int before = 1,
    int after = 1,
  });

  Future<List<Passage>> quoteCandidates(
    String translationId,
    List<String> tokens, {
    int limit = 40,
  });

  Future<List<SourcedPassage>> quoteCandidatesAcrossTranslations(
    List<String> tokens, {
    int limitPerTranslation = 40,
  });

  Future<String> fingerprint();

  Future<void> close();
}
