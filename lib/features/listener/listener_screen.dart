import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models.dart';
import '../bible/bible_repository.dart';
import '../semantic/semantic_retriever.dart';
import '../session/session_controller.dart';
import 'passage_sheet.dart';
import 'scripture_panel.dart';

typedef WakelockSetter = Future<void> Function(bool enabled);

class ListenerScreen extends StatefulWidget {
  const ListenerScreen({
    required this.controller,
    required this.repository,
    required this.displayTranslation,
    required this.semanticStatus,
    required this.serviceConfigured,
    this.setWakelock = _setWakelock,
    super.key,
  });

  final SessionController controller;
  final BibleRepository repository;
  final Translation displayTranslation;
  final ValueListenable<SemanticStatus> semanticStatus;
  final bool serviceConfigured;
  final WakelockSetter setWakelock;

  @override
  State<ListenerScreen> createState() => _ListenerScreenState();
}

class _ListenerScreenState extends State<ListenerScreen>
    with WidgetsBindingObserver {
  MatchCandidate? _promoted;
  MatchCandidate? _lastControllerFeatured;
  bool _wakelockEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
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
    final permissionPromptMayBeVisible =
        state == AppLifecycleState.inactive &&
        widget.controller.state.phase == SessionPhase.connecting;
    if (state != AppLifecycleState.resumed && !permissionPromptMayBeVisible) {
      unawaited(widget.controller.onAppBackgrounded());
    }
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

  Future<void> _showContext(MatchCandidate candidate) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => PassageSheet(
        repository: widget.repository,
        translationId: widget.displayTranslation.id,
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
      appBar: AppBar(title: const Text('John Mark'), centerTitle: false),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final state = widget.controller.state;
            if (!_isActive(state.phase)) {
              return ValueListenableBuilder<SemanticStatus>(
                valueListenable: widget.semanticStatus,
                builder: (context, semanticStatus, _) => _ReadyView(
                  state: state,
                  displayTranslation: widget.displayTranslation,
                  semanticStatus: semanticStatus,
                  serviceConfigured: widget.serviceConfigured,
                  onStart: widget.controller.start,
                ),
              );
            }
            return _ListeningView(
              state: state,
              displayTranslation: widget.displayTranslation,
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
    required this.displayTranslation,
    required this.semanticStatus,
    required this.serviceConfigured,
    required this.onStart,
  });

  final ListenerViewState state;
  final Translation displayTranslation;
  final SemanticStatus semanticStatus;
  final bool serviceConfigured;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final canStart = serviceConfigured;
    final colors = Theme.of(context).colorScheme;
    final displayName = _displayName(displayTranslation);
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
                  Semantics(
                    container: true,
                    label:
                        'Matches all bundled translations. Displays $displayName.',
                    child: Text(
                      'Matches all bundled translations · Displays $displayName',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
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
                  if (semanticStatus == SemanticStatus.unavailable) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Paraphrase matching unavailable · quotation matching remains active',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
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
    required this.displayTranslation,
    required this.promoted,
    required this.onPromote,
    required this.onFeaturedTap,
    required this.onStop,
  });

  final ListenerViewState state;
  final Translation displayTranslation;
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
                  if (!_isNkjv(displayTranslation)) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Displaying ${displayTranslation.name}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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

String _displayName(Translation translation) =>
    _isNkjv(translation) ? 'NKJV' : translation.name;

bool _isNkjv(Translation translation) {
  final id = translation.id.trim().toLowerCase();
  final name = translation.name.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  return id == 'nkjv' || name == 'new king james version';
}

Future<void> _setWakelock(bool enabled) =>
    enabled ? WakelockPlus.enable() : WakelockPlus.disable();
