import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/semantic/onnx_text_embedder.dart';
import 'package:john_mark/features/semantic/semantic_retriever.dart';
import 'package:john_mark/features/semantic/semantic_search_service.dart';

void main() {
  test(
    'holds the latest search while semantic components initialize',
    () async {
      final loading = Completer<SemanticComponents>();
      final embedder = _FakeEmbedder();
      final index = _FakeIndex();
      final service = SemanticSearchService(loadAssets: () => loading.future);
      addTearDown(service.dispose);

      final superseded = service.search('older finalized speech');
      final latest = service.search('latest finalized speech');
      expect(await superseded, isEmpty);

      loading.complete(SemanticComponents(embedder: embedder, index: index));

      expect(await latest, hasLength(1));
      expect(embedder.texts, ['latest finalized speech']);
      expect(service.status, SemanticStatus.ready);
    },
  );

  test('returns an empty result when initialization fails', () async {
    final service = SemanticSearchService(
      loadAssets: () => Future.error(StateError('unavailable')),
    );
    addTearDown(service.dispose);

    expect(await service.search('finalized speech'), isEmpty);
    expect(service.status, SemanticStatus.unavailable);
    expect(service.diagnosticCategory, 'StateError');
  });
}

class _FakeEmbedder implements TextEmbedder {
  final List<String> texts = [];

  @override
  Future<List<double>> embed(String text) async {
    texts.add(text);
    return const [1];
  }

  @override
  Future<void> dispose() async {}
}

class _FakeIndex implements SemanticVectorIndex {
  @override
  Future<List<SemanticHit>> search(List<double> query, {int limit = 8}) async =>
      const [
        SemanticHit(
          reference: ScriptureReference(
            book: 43,
            chapter: 3,
            startVerse: 16,
            endVerse: 16,
          ),
          translationId: 'alpha',
          score: 0.9,
        ),
      ];

  @override
  Future<void> dispose() async {}
}
