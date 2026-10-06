import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/models.dart';
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
import 'features/transcription/deepgram_client.dart';
import 'features/transcription/microphone_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = await SqliteBibleRepository.open();
    final translations = await repository.translations();
    final displayTranslation = resolveDisplayTranslation(translations);
    final semanticService = SemanticSearchService(
      loadAssets: () => _loadSemanticComponents(repository, translations),
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
    runApp(
      JohnMarkApp(
        home: _RuntimeHome(
          controller: controller,
          repository: repository,
          semanticService: semanticService,
          displayTranslation: displayTranslation,
          serviceConfigured: const String.fromEnvironment('DEEPGRAM_API_KEY')
              .isNotEmpty,
        ),
      ),
    );
    unawaited(semanticService.initialize());
  } catch (_) {
    runApp(const JohnMarkApp(home: _MissingBibleScreen()));
  }
}

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
  final tokenizer = await BgeTokenizer.fromAsset('assets/semantic/vocab.txt');
  final embedder = await OnnxTextEmbedder.load(
    tokenizer: tokenizer,
    dimensions: dimensions,
  );
  return SemanticComponents(embedder: embedder, index: index);
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

class _MissingBibleScreen extends StatelessWidget {
  const _MissingBibleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('John Mark')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              container: true,
              label: 'Bible database unavailable',
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined, size: 48),
                  SizedBox(height: 20),
                  Text(
                    'Bible database unavailable',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 12),
                  SelectableText(
                    'Build the bundled database before running the app:\n\n'
                    'dart run tool/build_bibles.dart <inputs> --output assets/bibles.db',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
