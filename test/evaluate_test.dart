import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/bible/bible_repository.dart';

import '../tool/evaluate.dart' as evaluator;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'scripture-evaluator-',
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('single transcript is evaluated as one unconfirmed window', () async {
    final fixtures = File('${temporaryDirectory.path}/single.ndjson');
    await fixtures.writeAsString(
      '{"translation":"test","transcript":"alpha beta gamma delta zeta eta",'
      '"expected":"John 1:1"}\n',
    );

    final metrics = await evaluator.evaluateFixtures(_Repository(), fixtures);

    expect(metrics.topOne, 0);
    expect(metrics.noResult, 1);
  });

  test('explicit ordered windows can confirm a possible match', () async {
    final fixtures = File('${temporaryDirectory.path}/windows.ndjson');
    await fixtures.writeAsString(
      '{"translation":"test","windows":['
      '"alpha beta gamma delta zeta eta",'
      '"alpha beta gamma delta zeta eta"],"expected":"John 1:1"}\n',
    );

    final metrics = await evaluator.evaluateFixtures(_Repository(), fixtures);

    expect(metrics.topOne, 1);
    expect(metrics.noResult, 0);
  });
}

class _Repository implements BibleRepository {
  static const passageValue = Passage(
    reference: ScriptureReference(
      book: 43,
      chapter: 1,
      startVerse: 1,
      endVerse: 1,
    ),
    label: 'John 1:1',
    text: 'alpha beta gamma delta epsilon',
  );

  @override
  Future<void> close() async {}

  @override
  Future<Passage?> context(
    String translationId,
    ScriptureReference reference, {
    int before = 1,
    int after = 1,
  }) async => passageValue;

  @override
  Future<Passage?> passage(
    String translationId,
    ScriptureReference reference,
  ) async => reference == passageValue.reference ? passageValue : null;

  @override
  Future<List<Passage>> quoteCandidates(
    String translationId,
    List<String> tokens, {
    int limit = 40,
  }) async => const [passageValue];

  @override
  Future<List<SourcedPassage>> quoteCandidatesAcrossTranslations(
    List<String> tokens, {
    int limitPerTranslation = 40,
  }) async => const [
    SourcedPassage(translationId: 'test', passage: passageValue),
  ];

  @override
  Future<String> fingerprint() async => 'fake-fingerprint';

  @override
  Future<List<Translation>> translations() async => const [
    Translation(id: 'test', name: 'Test'),
  ];
}
