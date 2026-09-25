import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/app.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/bible/bible_repository.dart';
import 'package:john_mark/features/listener/listener_screen.dart';
import 'package:john_mark/features/session/session_controller.dart';
import 'package:john_mark/features/transcription/transcription.dart';

void main() {
  testWidgets('runs the primary listener flow at phone and tablet sizes', (
    tester,
  ) async {
    final controller = _FakeSessionController();
    final repository = _FakeBibleRepository();
    final wakelockChanges = <bool>[];
    const translations = [
      Translation(id: 'nkjv', name: 'New King James Version'),
      Translation(id: 'kjv', name: 'King James Version'),
    ];

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
          child: JohnMarkApp(
            home: ListenerScreen(
              controller: controller,
              repository: repository,
              translations: translations,
              serviceConfigured: true,
              loadTranslationId: () async => 'nkjv',
              saveTranslationId: (_) async {},
              setWakelock: (enabled) async => wakelockChanges.add(enabled),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await pumpAt(const Size(390, 844));
    expect(find.text('John Mark'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('New King James Version'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);

    await tester.tap(find.text('Start Listening'));
    await tester.pump();
    expect(controller.startedWith?.id, 'nkjv');
    expect(find.text('Listening'), findsOneWidget);
    expect(wakelockChanges, [true]);

    controller.emit(
      ListenerViewState(
        phase: SessionPhase.listening,
        translation: translations.first,
        elapsed: const Duration(seconds: 37),
        transcript: const TranscriptUpdate(
          finalized: 'that whoever believes in him should not perish',
        ),
        matches: const MatchUpdate(
          featured: MatchCandidate(
            passage: Passage(
              reference: ScriptureReference(
                book: 43,
                chapter: 3,
                startVerse: 16,
                endVerse: 16,
              ),
              label: 'John 3:16',
              text: 'For God so loved the world that He gave His only Son.',
            ),
            score: 1,
            band: ConfidenceBand.high,
            explicitReference: true,
          ),
          alternatives: [
            MatchCandidate(
              passage: Passage(
                reference: ScriptureReference(
                  book: 45,
                  chapter: 5,
                  startVerse: 8,
                  endVerse: 8,
                ),
                label: 'Romans 5:8',
                text: 'God demonstrates His own love toward us.',
              ),
              score: 0.72,
              band: ConfidenceBand.possible,
              explicitReference: false,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('John 3:16'), findsOneWidget);
    expect(find.text('Romans 5:8'), findsOneWidget);
    expect(find.text('Current · High'), findsOneWidget);
    expect(find.textContaining('whoever believes'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('John 3:16'));
    await tester.tap(find.text('John 3:16'));
    await tester.pumpAndSettle();
    expect(find.text('John 3:15–17'), findsOneWidget);
    expect(find.text('Surrounding passage context.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Romans 5:8'));
    await tester.tap(find.text('Romans 5:8'));
    await tester.pump();
    expect(find.text('Romans 5:8'), findsOneWidget);

    await pumpAt(const Size(800, 900));
    expect(find.text('John 3:16'), findsWidgets);
    expect(find.text('LIVE TRANSCRIPT'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Stop Listening'));
    await tester.tap(find.text('Stop Listening'));
    await tester.pump();
    expect(find.text('Ready'), findsOneWidget);
    expect(wakelockChanges.last, false);
  });

  testWidgets('forwards non-resumed lifecycle states', (tester) async {
    final controller = _FakeSessionController();
    await tester.pumpWidget(
      JohnMarkApp(
        home: ListenerScreen(
          controller: controller,
          repository: _FakeBibleRepository(),
          translations: const [Translation(id: 'nkjv', name: 'NKJV')],
          serviceConfigured: true,
          loadTranslationId: () async => 'nkjv',
          saveTranslationId: (_) async {},
          setWakelock: (_) async {},
        ),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(controller.backgroundCount, 1);
  });

  testWidgets('does not treat a permission prompt as backgrounding', (
    tester,
  ) async {
    final controller = _FakeSessionController();
    await tester.pumpWidget(
      JohnMarkApp(
        home: ListenerScreen(
          controller: controller,
          repository: _FakeBibleRepository(),
          translations: const [Translation(id: 'nkjv', name: 'NKJV')],
          serviceConfigured: true,
          loadTranslationId: () async => 'nkjv',
          saveTranslationId: (_) async {},
          setWakelock: (_) async {},
        ),
      ),
    );
    await tester.pump();
    controller.emit(
      const ListenerViewState(
        phase: SessionPhase.connecting,
        translation: Translation(id: 'nkjv', name: 'NKJV'),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.backgroundCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(controller.backgroundCount, 1);
  });
}

class _FakeSessionController extends SessionController {
  _FakeSessionController()
    : super(
        audioSource: _UnusedAudioSource(),
        transcriptionClient: _UnusedTranscriptionClient(),
        matchTranscript: (_, _) async => null,
        resetMatcher: () {},
      );

  ListenerViewState _fakeState = const ListenerViewState();
  Translation? startedWith;
  int backgroundCount = 0;

  @override
  ListenerViewState get state => _fakeState;

  @override
  Future<void> start(Translation translation) async {
    startedWith = translation;
    emit(
      ListenerViewState(
        phase: SessionPhase.listening,
        translation: translation,
      ),
    );
  }

  @override
  Future<void> stop() async {
    emit(const ListenerViewState(phase: SessionPhase.stopped));
  }

  @override
  Future<void> onAppBackgrounded() async {
    backgroundCount++;
    await stop();
  }

  void emit(ListenerViewState state) {
    _fakeState = state;
    notifyListeners();
  }
}

class _FakeBibleRepository implements BibleRepository {
  @override
  Future<void> close() async {}

  @override
  Future<Passage?> context(
    String translationId,
    ScriptureReference reference, {
    int before = 1,
    int after = 1,
  }) async => const Passage(
    reference: ScriptureReference(
      book: 43,
      chapter: 3,
      startVerse: 15,
      endVerse: 17,
    ),
    label: 'John 3:15–17',
    text: 'Surrounding passage context.',
  );

  @override
  Future<Passage?> passage(
    String translationId,
    ScriptureReference reference,
  ) async => null;

  @override
  Future<List<Passage>> quoteCandidates(
    String translationId,
    List<String> tokens, {
    int limit = 40,
  }) async => const [];

  @override
  Future<List<Translation>> translations() async => const [];
}

class _UnusedAudioSource implements AudioSource {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> start() async => const Stream.empty();

  @override
  Future<void> stop() async {}
}

class _UnusedTranscriptionClient implements TranscriptionClient {
  @override
  Future<TranscriptionConnection> open({required List<String> keyterms}) {
    throw UnimplementedError();
  }
}
