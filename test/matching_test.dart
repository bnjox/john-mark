import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/bible/bible_repository.dart';
import 'package:john_mark/features/matching/reference_parser.dart';
import 'package:john_mark/features/matching/scripture_matcher.dart';
import 'package:john_mark/features/semantic/bge_tokenizer.dart';
import 'package:john_mark/features/semantic/semantic_retriever.dart';

void main() {
  const john316 = Passage(
    reference: ScriptureReference(
      book: 43,
      chapter: 3,
      startVerse: 16,
      endVerse: 16,
    ),
    label: 'John 3:16',
    text: 'The Maker cherished the world and offered the beloved Son.',
  );
  const corinthians = Passage(
    reference: ScriptureReference(
      book: 46,
      chapter: 13,
      startVerse: 4,
      endVerse: 7,
    ),
    label: '1 Corinthians 13:4–7',
    text: 'Love is patient and kind.',
  );

  test('BGE tokenizer retains the newest tokens when input is too long', () {
    final tokenizer = BgeTokenizer.fromVocabulary(
      '[UNK]\n[CLS]\n[SEP]\nold\nnew\none\ntwo\nthree',
    );

    final inputs = tokenizer.encode(
      'old old old new one two three',
      maxLength: 5,
    );

    expect(inputs.inputIds, [1, 5, 6, 7, 2]);
  });

  test('BGE tokenizer does not pad short input to the model maximum', () {
    final tokenizer = BgeTokenizer.fromVocabulary(
      '[UNK]\n[CLS]\n[SEP]\nshort\nquery',
    );

    final inputs = tokenizer.encode('short query');

    expect(inputs.inputIds, [1, 3, 4, 2]);
    expect(inputs.attentionMask, [1, 1, 1, 1]);
    expect(inputs.tokenTypeIds, [0, 0, 0, 0]);
  });

  group('ReferenceParser', () {
    const parser = ReferenceParser();

    test('parses compact, numbered-book, and range references', () {
      expect(parser.parse('John three sixteen'), john316.reference);
      expect(
        parser.parse('First Corinthians thirteen four through seven'),
        corinthians.reference,
      );
      expect(parser.parse('First John chapter three verse sixteen')?.book, 62);
    });

    test('returns the latest reference and rejects ordinary speech', () {
      expect(
        parser.parse(
          'John three sixteen, then First Corinthians thirteen four to seven',
        ),
        corinthians.reference,
      );
      expect(parser.parse('John spoke for three minutes'), isNull);
    });
  });

  group('ScriptureMatcher', () {
    test('resolves an explicit reference without running the model', () async {
      final semantic = _FakeSemanticRetriever([
        SemanticHit(
          reference: corinthians.reference,
          translationId: 'alpha',
          score: 0.95,
        ),
      ]);
      final matcher = _matcher(
        passages: [john316, corinthians],
        semantic: semantic,
      );

      final update = await matcher.match(
        'older paraphrase\nplease open John chapter three verse sixteen',
      );

      expect(update?.featured?.passage, john316);
      expect(update?.featured?.score, 1);
      expect(update?.alternatives, isEmpty);
      expect(semantic.queries, isEmpty);
    });

    test('ranks, deduplicates, and thresholds semantic results', () async {
      final psalms = [
        for (var verse = 1; verse <= 4; verse++)
          Passage(
            reference: ScriptureReference(
              book: 19,
              chapter: 1,
              startVerse: verse,
              endVerse: verse,
            ),
            label: 'Psalm 1:$verse',
            text: 'Psalm candidate $verse.',
          ),
      ];
      final semantic = _FakeSemanticRetriever([
        SemanticHit(
          reference: corinthians.reference,
          translationId: 'beta',
          score: 0.84,
        ),
        SemanticHit(
          reference: john316.reference,
          translationId: 'alpha',
          score: 0.91,
        ),
        SemanticHit(
          reference: corinthians.reference,
          translationId: 'alpha',
          score: 0.86,
        ),
        for (var index = 0; index < psalms.length; index++)
          SemanticHit(
            reference: psalms[index].reference,
            translationId: 'alpha',
            score: switch (index) {
              0 => 0.85,
              1 => 0.79,
              2 => 0.74,
              _ => 0.73,
            },
          ),
        const SemanticHit(
          reference: ScriptureReference(
            book: 1,
            chapter: 1,
            startVerse: 1,
            endVerse: 1,
          ),
          translationId: 'alpha',
          score: 0.81,
        ),
      ]);
      final matcher = _matcher(
        passages: [john316, corinthians, ...psalms],
        semantic: semantic,
      );

      final update = await matcher.match('a paraphrase across recent speech');

      expect(update?.featured?.passage, john316);
      expect(update?.featured?.band, ConfidenceBand.high);
      expect(update?.alternatives.map((candidate) => candidate.passage.label), [
        '1 Corinthians 13:4–7',
        'Psalm 1:1',
        'Psalm 1:2',
      ]);
      expect(update?.alternatives.last.score, 0.79);
      expect(update?.alternatives.first.band, ConfidenceBand.possible);
      expect(semantic.queries, ['a paraphrase across recent speech']);
    });

    test(
      'returns no update when the model is unavailable or uncertain',
      () async {
        final unavailable = _matcher(
          passages: [john316],
          semantic: _FakeSemanticRetriever(
            const [],
            status: SemanticStatus.unavailable,
          ),
        );
        final uncertain = _matcher(
          passages: [john316],
          semantic: _FakeSemanticRetriever([
            SemanticHit(
              reference: john316.reference,
              translationId: 'alpha',
              score: 0.81,
            ),
          ]),
        );

        expect(await unavailable.match('ordinary speech'), isNull);
        expect(await uncertain.match('ordinary speech'), isNull);
      },
    );
  });
}

ScriptureMatcher _matcher({
  required List<Passage> passages,
  required SemanticRetriever semantic,
}) => ScriptureMatcher(
  repository: _FakeBibleRepository(passages),
  displayTranslation: const Translation(id: 'alpha', name: 'Alpha'),
  semanticRetriever: semantic,
);

class _FakeBibleRepository implements BibleRepository {
  _FakeBibleRepository(this.passages);

  final List<Passage> passages;

  @override
  Future<Passage?> passage(
    String translationId,
    ScriptureReference reference,
  ) async {
    for (final passage in passages) {
      if (passage.reference == reference) return passage;
    }
    return null;
  }

  @override
  Future<List<Translation>> translations() async => const [
    Translation(id: 'alpha', name: 'Alpha'),
  ];

  @override
  Future<Passage?> context(
    String translationId,
    ScriptureReference reference, {
    int before = 1,
    int after = 1,
  }) => passage(translationId, reference);

  @override
  Future<String> fingerprint() async => 'fake-fingerprint';

  @override
  Future<void> close() async {}
}

class _FakeSemanticRetriever implements SemanticRetriever {
  _FakeSemanticRetriever(this.hits, {this.status = SemanticStatus.ready});

  final List<SemanticHit> hits;
  @override
  final SemanticStatus status;
  final List<String> queries = [];

  @override
  Future<List<SemanticHit>> search(String text, {int limit = 8}) async {
    queries.add(text);
    return hits.take(limit).toList(growable: false);
  }
}
