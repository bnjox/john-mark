import 'package:flutter/material.dart';

import 'app.dart';
import 'features/bible/sqlite_bible_repository.dart';
import 'features/listener/listener_screen.dart';
import 'features/matching/scripture_matcher.dart';
import 'features/session/session_controller.dart';
import 'features/transcription/deepgram_client.dart';
import 'features/transcription/microphone_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = await SqliteBibleRepository.open();
    final translations = await repository.translations();
    final matchers = <String, ScriptureMatcher>{};
    final controller = SessionController(
      audioSource: MicrophoneSource(),
      transcriptionClient: const DeepgramClient(),
      matchTranscript: (translationId, text) => matchers
          .putIfAbsent(
            translationId,
            () => ScriptureMatcher(
              repository: repository,
              translationId: translationId,
            ),
          )
          .match(text),
    );
    runApp(
      ScriptureListenerApp(
        home: ListenerScreen(
          controller: controller,
          repository: repository,
          translations: translations,
          serviceConfigured: const String.fromEnvironment('DEEPGRAM_API_KEY')
              .isNotEmpty,
        ),
      ),
    );
  } catch (_) {
    runApp(const ScriptureListenerApp(home: _MissingBibleScreen()));
  }
}

class _MissingBibleScreen extends StatelessWidget {
  const _MissingBibleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scripture Listener')),
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
