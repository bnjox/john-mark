import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models.dart';
import '../bible/bible_repository.dart';
import '../session/session_controller.dart';
import 'passage_sheet.dart';
import 'scripture_panel.dart';

typedef TranslationIdLoader = Future<String?> Function();
typedef TranslationIdSaver = Future<void> Function(String id);
typedef WakelockSetter = Future<void> Function(bool enabled);

class ListenerScreen extends StatefulWidget {
  const ListenerScreen({
    required this.controller,
    required this.repository,
    required this.translations,
    required this.serviceConfigured,
    this.loadTranslationId = _loadTranslationId,
    this.saveTranslationId = _saveTranslationId,
    this.setWakelock = _setWakelock,
    super.key,
  });

  final SessionController controller;
  final BibleRepository repository;
  final List<Translation> translations;
  final bool serviceConfigured;
  final TranslationIdLoader loadTranslationId;
  final TranslationIdSaver saveTranslationId;
  final WakelockSetter setWakelock;

  @override
  State<ListenerScreen> createState() => _ListenerScreenState();
}

class _ListenerScreenState extends State<ListenerScreen>
    with WidgetsBindingObserver {
  Translation? _selectedTranslation;
  MatchCandidate? _promoted;
  MatchCandidate? _lastControllerFeatured;
  bool _wakelockEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    _restoreTranslation();
  }

  @override
  void didUpdateWidget(covariant ListenerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.controller.onAppBackgrounded());
    }
  }

  Future<void> _restoreTranslation() async {
    final savedId = await widget.loadTranslationId();
    if (!mounted) return;
    final saved = widget.translations.where((item) => item.id == savedId);
    setState(() {
      _selectedTranslation = saved.isNotEmpty
          ? saved.first
          : widget.translations.firstOrNull;
    });
  }

  void _onControllerChanged() {
    final state = widget.controller.state;
    if (!identical(_lastControllerFeatured, state.matches.featured)) {
      _lastControllerFeatured = state.matches.featured;
      _promoted = null;
    }
    final shouldWake = _isActive(state.phase);
    if (shouldWake != _wakelockEnabled) {
      _wakelockEnabled = shouldWake;
      unawaited(widget.setWakelock(shouldWake));
    }
    if (mounted) setState(() {});
  }

  Future<void> _selectTranslation(Translation? translation) async {
    if (translation == null || _isActive(widget.controller.state.phase)) return;
    setState(() => _selectedTranslation = translation);
    await widget.saveTranslationId(translation.id);
  }

  Future<void> _showContext(MatchCandidate candidate) async {
    final translation =
        widget.controller.state.translation ?? _selectedTranslation;
    if (translation == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => PassageSheet(
        repository: widget.repository,
        translationId: translation.id,
        passage: candidate.passage,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    if (_wakelockEnabled) unawaited(widget.setWakelock(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scripture Listener'),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final state = widget.controller.state;
            if (!_isActive(state.phase)) {
              return _ReadyView(
                state: state,
                translations: widget.translations,
                selectedTranslation: _selectedTranslation,
                serviceConfigured: widget.serviceConfigured,
                onTranslationChanged: _selectTranslation,
                onStart: _selectedTranslation == null
                    ? null
                    : () => widget.controller.start(_selectedTranslation!),
              );
            }
            return _ListeningView(
              state: state,
              promoted: _promoted,
              onPromote: (candidate) => setState(() => _promoted = candidate),
              onFeaturedTap: _showContext,
              onStop: widget.controller.stop,
            );
          },
        ),
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.state,
    required this.translations,
    required this.selectedTranslation,
    required this.serviceConfigured,
    required this.onTranslationChanged,
    required this.onStart,
  });

  final ListenerViewState state;
  final List<Translation> translations;
  final Translation? selectedTranslation;
  final bool serviceConfigured;
  final ValueChanged<Translation?> onTranslationChanged;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final canStart = serviceConfigured && selectedTranslation != null;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Semantics(
              container: true,
              label: 'Ready to listen',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusLine(phase: state.phase, elapsed: state.elapsed),
                  const SizedBox(height: 32),
                  Text(
                    'Translation',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Translation>(
                    initialValue: selectedTranslation,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    hint: const Text('Select a translation'),
                    items: translations
                        .map(
                          (translation) => DropdownMenuItem(
                            value: translation,
                            child: Text(translation.name),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: onTranslationChanged,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Microphone',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 56,
                    leading: const Icon(Icons.mic_outlined),
                    title: const Text('Built-in microphone'),
                    subtitle: const Text(
                      'Used only while this screen is active',
                    ),
                  ),
                  if (state.message != null) ...[
                    const SizedBox(height: 12),
                    Text(state.message!, style: TextStyle(color: colors.error)),
                  ],
                  if (!serviceConfigured) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Transcription service is not configured for this build.',
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                  if (translations.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No Bible translations are available.',
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: canStart ? onStart : null,
                    icon: const Icon(Icons.graphic_eq),
                    label: const Text('Start Listening'),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    label: 'Privacy notice',
                    child: Text(
                      'Audio is sent to Deepgram for transcription and is not saved by this app. Transcript and passage history are cleared when listening stops.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
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

class _ListeningView extends StatelessWidget {
  const _ListeningView({
    required this.state,
    required this.promoted,
    required this.onPromote,
    required this.onFeaturedTap,
    required this.onStop,
  });

  final ListenerViewState state;
  final MatchCandidate? promoted;
  final ValueChanged<MatchCandidate> onPromote;
  final ValueChanged<MatchCandidate> onFeaturedTap;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final controllerFeatured = state.matches.featured;
    final featured = promoted ?? controllerFeatured;
    final alternatives = <MatchCandidate>[
      if (promoted != null && controllerFeatured != null) controllerFeatured,
      ...state.matches.alternatives.where((item) => !identical(item, promoted)),
    ].take(3).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final scripture = ScripturePanel(
          featured: featured,
          alternatives: alternatives,
          isStale: state.resultIsStale,
          onFeaturedTap: featured == null
              ? null
              : () => onFeaturedTap(featured),
          onAlternativeTap: onPromote,
        );
        final transcript = _TranscriptPanel(transcript: state.transcript);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusLine(phase: state.phase, elapsed: state.elapsed),
                  const SizedBox(height: 24),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: scripture),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: transcript),
                      ],
                    )
                  else ...[
                    scripture,
                    const SizedBox(height: 32),
                    transcript,
                  ],
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop Listening'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({required this.transcript});

  final TranscriptUpdate transcript;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = [
      transcript.finalized.trim(),
      transcript.interim.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Live transcript',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LIVE TRANSCRIPT',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              text.isEmpty ? 'Waiting for speech…' : text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: text.isEmpty
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.phase, required this.elapsed});

  final SessionPhase phase;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final label = _phaseLabel(phase);
    final active = _isActive(phase);
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      label:
          'Session status: $label${active ? ', ${_formatDuration(elapsed)}' : ''}',
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.radio_button_checked : Icons.circle_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (active)
            Text(
              _formatDuration(elapsed),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

bool _isActive(SessionPhase phase) => switch (phase) {
  SessionPhase.connecting ||
  SessionPhase.listening ||
  SessionPhase.silence ||
  SessionPhase.reconnecting ||
  SessionPhase.delayed => true,
  _ => false,
};

String _phaseLabel(SessionPhase phase) => switch (phase) {
  SessionPhase.ready || SessionPhase.stopped => 'Ready',
  SessionPhase.connecting => 'Connecting…',
  SessionPhase.listening => 'Listening',
  SessionPhase.silence => 'Listening · quiet',
  SessionPhase.reconnecting => 'Reconnecting…',
  SessionPhase.delayed => 'Live audio delayed',
  SessionPhase.permissionDenied => 'Microphone blocked',
  SessionPhase.serviceError => 'Service unavailable',
};

String _formatDuration(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

Future<String?> _loadTranslationId() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getString('selected_translation_id');
}

Future<void> _saveTranslationId(String id) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString('selected_translation_id', id);
}

Future<void> _setWakelock(bool enabled) =>
    enabled ? WakelockPlus.enable() : WakelockPlus.disable();
