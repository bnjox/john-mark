import 'package:flutter_test/flutter_test.dart';
import 'package:guide/core/models.dart';
import 'package:guide/features/bible/bible_repository.dart';
import 'package:guide/features/matching/match_stabilizer.dart';
import 'package:guide/features/matching/quote_matcher.dart';
import 'package:guide/features/matching/reference_parser.dart';
import 'package:guide/features/matching/scripture_matcher.dart';

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
    text:
        'Love is patient and kind. Love does not envy or boast. '
        'It protects, trusts, hopes, and perseveres.',
  );

  group('ReferenceParser', () {
    test('parses compact spoken and ordinal range references', () async {
      final repository = _FakeBibleRepository({
        'alpha': [john316, corinthians],
      });
      final parser = ReferenceParser(repository);

      final compact = await parser.parse('John three sixteen', 'alpha');
      final range = await parser.parse(
        'First Corinthians thirteen four through seven',
        'alpha',
      );

      expect(compact?.passage.label, 'John 3:16');
      expect(compact?.score, 1);
      expect(compact?.band, ConfidenceBand.high);
      expect(compact?.explicitReference, isTrue);
      expect(range?.passage.label, '1 Corinthians 13:4–7');
    });

    test('rejects ordinary speech containing a book name and number', () async {
      final parser = ReferenceParser(
        _FakeBibleRepository({
          'alpha': [john316],
        }),
      );

      expect(
        await parser.parse('John spoke for three minutes', 'alpha'),
        isNull,
      );
    });
  });

  group('QuoteMatcher', () {
    test('accepts exact and close imperfect quotations', () async {
      final matcher = QuoteMatcher(
        _FakeBibleRepository({
          'alpha': [john316],
        }),
      );

      final exact = await matcher.match(john316.text, 'alpha');
      final imperfect = await matcher.match(
        'The maker cherished the whole world then offered his beloved son',
        'alpha',
      );

      expect(exact.single.passage.label, 'John 3:16');
      expect(exact.single.score, 1);
      expect(imperfect.single.passage.label, 'John 3:16');
      expect(imperfect.single.score, greaterThanOrEqualTo(0.78));
    });

    test('rejects unrelated and ambiguous short speech', () async {
      final matcher = QuoteMatcher(
        _FakeBibleRepository({
          'alpha': [john316, corinthians],
        }),
      );

      expect(
        await matcher.match('Please move the camera to the left', 'alpha'),
        isEmpty,
      );
      expect(await matcher.match('love one another', 'alpha'), isEmpty);
    });

    test('searches only the selected translation', () async {
      const otherTranslation = Passage(
        reference: ScriptureReference(
          book: 43,
          chapter: 3,
          startVerse: 16,
          endVerse: 16,
        ),
        label: 'John 3:16',
        text: 'Completely different wording in the second translation.',
      );
      final repository = _FakeBibleRepository({
        'alpha': [john316],
        'beta': [otherTranslation],
      });
      final matcher = QuoteMatcher(repository);

      final matches = await matcher.match(john316.text, 'alpha');

      expect(matches.single.passage.text, john316.text);
      expect(repository.queriedTranslations, ['alpha']);
    });
  });

  group('MatchStabilizer', () {
    const config = MatchConfig();

    test(
      'shows strong matches immediately and suppresses unchanged updates',
      () {
        final stabilizer = MatchStabilizer(config);
        final candidate = _candidate(john316, 0.9);

        expect(stabilizer.update([candidate])?.featured, same(candidate));
        expect(stabilizer.update([candidate]), isNull);
      },
    );

    test('requires two windows for possible matches', () {
      final stabilizer = MatchStabilizer(config);
      final candidate = _candidate(john316, 0.7);

      expect(stabilizer.update([candidate]), isNull);
      expect(stabilizer.update([candidate])?.featured, same(candidate));
    });

    test(
      'does not replace a stronger result without the configured margin',
      () {
        final stabilizer = MatchStabilizer(config);
        final first = _candidate(john316, 0.9);
        final second = _candidate(corinthians, 0.95);

        expect(stabilizer.update([first])?.featured, same(first));
        expect(stabilizer.update([second]), isNull);
        expect(stabilizer.current.featured, same(first));
      },
    );

    test('returns at most three distinct alternatives', () {
      final featured = _candidate(john316, 0.95);
      final candidates = <MatchCandidate>[
        featured,
        featured,
        for (var verse = 1; verse <= 5; verse++)
          _candidate(
            Passage(
              reference: ScriptureReference(
                book: 19,
                chapter: 1,
                startVerse: verse,
                endVerse: verse,
              ),
              label: 'Psalm 1:$verse',
              text: 'Candidate passage number $verse with sufficient wording.',
            ),
            0.8 - verse / 100,
          ),
      ];

      final update = MatchStabilizer(config).update(candidates)!;

      expect(update.alternatives, hasLength(3));
      expect(
        update.alternatives.map((candidate) => candidate.passage.label).toSet(),
        hasLength(3),
      );
    });
  });

  test(
    'ScriptureMatcher gives validated references priority over quotes',
    () async {
      final matcher = ScriptureMatcher(
        repository: _FakeBibleRepository({
          'alpha': [john316, corinthians],
        }),
        translationId: 'alpha',
      );

      final update = await matcher.match(
        'The maker cherished the world. John chapter three verse sixteen.',
      );

      expect(update?.featured?.passage.label, 'John 3:16');
      expect(update?.featured?.explicitReference, isTrue);
    },
  );
}

MatchCandidate _candidate(Passage passage, double score) => MatchCandidate(
  passage: passage,
  score: score,
  band: score >= 0.78 ? ConfidenceBand.high : ConfidenceBand.possible,
  explicitReference: false,
);

class _FakeBibleRepository implements BibleRepository {
  _FakeBibleRepository(this.passagesByTranslation);

  final Map<String, List<Passage>> passagesByTranslation;
  final List<String> queriedTranslations = [];

  @override
  Future<Passage?> passage(
    String translationId,
    ScriptureReference reference,
  ) async {
    for (final passage in passagesByTranslation[translationId] ?? const []) {
      if (_sameReference(passage.reference, reference)) return passage;
    }
    return null;
  }

  @override
  Future<List<Passage>> quoteCandidates(
    String translationId,
    List<String> tokens, {
    int limit = 40,
  }) async {
    queriedTranslations.add(translationId);
    return (passagesByTranslation[translationId] ?? const [])
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<Translation>> translations() async => passagesByTranslation.keys
      .map((id) => Translation(id: id, name: id))
      .toList(growable: false);

  @override
  Future<Passage?> context(
    String translationId,
    ScriptureReference reference, {
    int before = 1,
    int after = 1,
  }) => passage(translationId, reference);

  @override
  Future<void> close() async {}
}

bool _sameReference(ScriptureReference left, ScriptureReference right) =>
    left.book == right.book &&
    left.chapter == right.chapter &&
    left.startVerse == right.startVerse &&
    left.endVerse == right.endVerse;
