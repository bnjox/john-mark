import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/models.dart';
import 'core/performance_trace.dart';
import 'features/bible/bible_repository.dart';
import 'features/bible/display_translation_resolver.dart';
import 'features/bible/sqlite_bible_repository.dart';
import 'features/listener/listener_screen.dart';
import 'features/matching/scripture_matcher.dart';
import 'features/semantic/bge_tokenizer.dart';
import 'features/semantic/onnx_text_embedder.dart';
import 'features/semantic/semantic_index.dart';
import 'features/semantic/semantic_search_service.dart';
import 'features/session/session_controller.dart';
import 'features/startup/runtime_bootstrap_screen.dart';
import 'features/transcription/deepgram_client.dart';
import 'features/transcription/microphone_source.dart';

void main() {
  final started = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    started.stop();
    recordPerformance('startup.first_frame', started.elapsed);
  });
  runApp(JohnMarkApp(home: RuntimeBootstrapScreen(loadHome: _loadRuntimeHome)));
}

Future<Widget> _loadRuntimeHome() =>
    tracePerformance('startup.runtime_ready', () async {
      BibleRepository? repository;
      SemanticSearchService? semanticService;
      try {
        repository = await SqliteBibleRepository.open();
        final translations = await repository.translations();
        final displayTranslation = resolveDisplayTranslation(translations);
        semanticService = SemanticSearchService(
          loadAssets: () => _loadSemanticComponents(repository!, translations),
        );
        final matcher = ScriptureMatcher(
          repository: repository,
          displayTranslation: displayTranslation,
          semanticRetriever: semanticService,
        );
        final controller = SessionController(
          audioSource: MicrophoneSource(),
          transcriptionClient: const DeepgramClient(),
          matchTranscript: matcher.match,
        );
        unawaited(semanticService.initialize());
        return _RuntimeHome(
          controller: controller,
          repository: repository,
          semanticService: semanticService,
          displayTranslation: displayTranslation,
          serviceConfigured: const String.fromEnvironment('DEEPGRAM_API_KEY')
              .isNotEmpty,
        );
      } catch (_) {
        semanticService?.dispose();
        await repository?.close();
        rethrow;
      }
    });

Future<SemanticComponents> _loadSemanticComponents(
  BibleRepository repository,
  List<Translation> translations,
) async {
  const modelId = 'BAAI/bge-base-en-v1.5';
  const modelRevision = 'a5beb1e3e68b9ab74eb54cfd186867f64f240e1a';
  const dimensions = 768;
  final fingerprint = await repository.fingerprint();
  final index = await SemanticIndex.loadAsset(
    'assets/semantic/scripture_embeddings.bin',
    rootIsolateToken: RootIsolateToken.instance!,
    expectedModelId: modelId,
    expectedModelRevision: modelRevision,
    expectedDimensions: dimensions,
    expectedBibleFingerprint: fingerprint,
    expectedTranslationIds: translations.map((translation) => translation.id),
  );
  try {
    final tokenizer = await BgeTokenizer.fromAsset('assets/semantic/vocab.txt');
    final embedder = await OnnxTextEmbedder.load(
      tokenizer: tokenizer,
      dimensions: dimensions,
    );
    return SemanticComponents(embedder: embedder, index: index);
  } catch (_) {
    await index.dispose();
    rethrow;
  }
}

class _RuntimeHome extends StatefulWidget {
  const _RuntimeHome({
    required this.controller,
    required this.repository,
    required this.semanticService,
    required this.displayTranslation,
    required this.serviceConfigured,
  });

  final SessionController controller;
  final BibleRepository repository;
  final SemanticSearchService semanticService;
  final Translation displayTranslation;
  final bool serviceConfigured;

  @override
  State<_RuntimeHome> createState() => _RuntimeHomeState();
}

class _RuntimeHomeState extends State<_RuntimeHome> {
  @override
  void dispose() {
    widget.controller.dispose();
    widget.semanticService.dispose();
    unawaited(widget.repository.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenerScreen(
    controller: widget.controller,
    repository: widget.repository,
    displayTranslation: widget.displayTranslation,
    semanticStatus: widget.semanticService,
    serviceConfigured: widget.serviceConfigured,
  );
}
