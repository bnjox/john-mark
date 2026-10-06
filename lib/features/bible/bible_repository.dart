import '../../core/models.dart';

abstract interface class BibleRepository {
  Future<List<Translation>> translations();

  Future<Passage?> passage(String translationId, ScriptureReference reference);

  Future<Passage?> context(
    String translationId,
    ScriptureReference reference, {
    int before = 1,
    int after = 1,
  });

  Future<String> fingerprint();

  Future<void> close();
}
