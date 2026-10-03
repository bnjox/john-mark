enum SessionPhase {
  ready,
  connecting,
  listening,
  silence,
  reconnecting,
  delayed,
  stopped,
  permissionDenied,
  serviceError,
}

enum ConfidenceBand { high, possible }

class Translation {
  const Translation({required this.id, required this.name});

  final String id;
  final String name;
}

class ScriptureReference {
  const ScriptureReference({
    required this.book,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
  });

  final int book;
  final int chapter;
  final int startVerse;
  final int endVerse;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptureReference &&
          book == other.book &&
          chapter == other.chapter &&
          startVerse == other.startVerse &&
          endVerse == other.endVerse;

  @override
  int get hashCode => Object.hash(book, chapter, startVerse, endVerse);
}

class Passage {
  const Passage({
    required this.reference,
    required this.label,
    required this.text,
  });

  final ScriptureReference reference;
  final String label;
  final String text;
}

class MatchCandidate {
  const MatchCandidate({
    required this.passage,
    required this.score,
    required this.band,
    required this.explicitReference,
  });

  final Passage passage;
  final double score;
  final ConfidenceBand band;
  final bool explicitReference;
}

class MatchUpdate {
  const MatchUpdate({this.featured, this.alternatives = const []});

  final MatchCandidate? featured;
  final List<MatchCandidate> alternatives;
}

class TranscriptUpdate {
  const TranscriptUpdate({this.finalized = '', this.interim = ''});

  final String finalized;
  final String interim;
}

class ListenerViewState {
  const ListenerViewState({
    this.phase = SessionPhase.ready,
    this.transcript = const TranscriptUpdate(),
    this.matches = const MatchUpdate(),
    this.elapsed = Duration.zero,
    this.message,
    this.resultIsStale = false,
  });

  final SessionPhase phase;
  final TranscriptUpdate transcript;
  final MatchUpdate matches;
  final Duration elapsed;
  final String? message;
  final bool resultIsStale;
}
