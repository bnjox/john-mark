import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/bible/display_translation_resolver.dart';
import 'package:john_mark/features/bible/sqlite_bible_repository.dart';
import 'package:john_mark/features/matching/scripture_matcher.dart';
import 'package:john_mark/features/semantic/bge_tokenizer.dart';
import 'package:john_mark/features/semantic/onnx_text_embedder.dart';
import 'package:john_mark/features/semantic/semantic_index.dart';
import 'package:john_mark/features/semantic/semantic_retriever.dart';
import 'package:john_mark/features/semantic/semantic_search_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exact semantic searches finish within five seconds', (_) async {
    final repository = await SqliteBibleRepository.open();
    final translations = await repository.translations();
    final initialization = Stopwatch()..start();
    final index = await SemanticIndex.loadAsset(
      'assets/semantic/scripture_embeddings.bin',
      expectedModelId: 'BAAI/bge-base-en-v1.5',
      expectedModelRevision: 'a5beb1e3e68b9ab74eb54cfd186867f64f240e1a',
      expectedDimensions: 768,
      expectedBibleFingerprint: await repository.fingerprint(),
      expectedTranslationIds: translations.map((value) => value.id),
    );
    final embedder = await OnnxTextEmbedder.load(
      tokenizer: await BgeTokenizer.fromAsset('assets/semantic/vocab.txt'),
    );
    initialization.stop();
    debugPrint(
      'semantic_initialization_ms=${initialization.elapsedMilliseconds}',
    );

    final service = SemanticSearchService(
      loadAssets: () async =>
          SemanticComponents(embedder: embedder, index: index),
    );
    addTearDown(() async {
      service.dispose();
      await repository.close();
    });
    await service.initialize();
    expect(service.status, SemanticStatus.ready);

    for (final query in [
      'God loved the world and gave his son',
      'I can endure every circumstance through the one who strengthens me',
      'The Lord guides me like a shepherd and I lack nothing',
    ]) {
      final stopwatch = Stopwatch()..start();
      final embedding = await embedder.embed(query);
      final hits = await index.search(embedding);
      stopwatch.stop();
      debugPrint('semantic_search_ms=${stopwatch.elapsedMilliseconds}');
      expect(hits, isNotEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    }

    final matcher = ScriptureMatcher(
      repository: repository,
      displayTranslation: resolveDisplayTranslation(translations),
      semanticRetriever: service,
    );
    const introduction =
        'Good morning everyone.\n'
        'Thank you for joining us today.\n'
        'Please take your seats.\n'
        'Let us begin the message.\n';
    for (final (query, expected) in [
      (
        '${introduction}God loved the world and gave his son',
        const ScriptureReference(
          book: 43,
          chapter: 3,
          startVerse: 16,
          endVerse: 16,
        ),
      ),
      (
        '${introduction}The Lord guides me like a shepherd and I lack nothing',
        const ScriptureReference(
          book: 19,
          chapter: 23,
          startVerse: 1,
          endVerse: 1,
        ),
      ),
      (
        'The Lord guides me like a shepherd\nand I lack nothing',
        const ScriptureReference(
          book: 19,
          chapter: 23,
          startVerse: 1,
          endVerse: 1,
        ),
      ),
    ]) {
      final stopwatch = Stopwatch()..start();
      final update = await matcher.match(query);
      stopwatch.stop();
      debugPrint('semantic_match_ms=${stopwatch.elapsedMilliseconds}');
      expect(update?.featured?.passage.reference, expected);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    }
  });
}
