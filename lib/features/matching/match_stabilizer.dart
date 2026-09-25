import '../../core/models.dart';

class MatchConfig {
  const MatchConfig({
    this.strongThreshold = 0.78,
    this.possibleThreshold = 0.68,
    this.replacementMargin = 0.06,
    this.confirmationWindows = 2,
  });

  final double strongThreshold;
  final double possibleThreshold;
  final double replacementMargin;
  final int confirmationWindows;
}

class MatchStabilizer {
  MatchStabilizer(this.config)
    : assert(config.confirmationWindows > 0),
      assert(config.possibleThreshold <= config.strongThreshold);

  final MatchConfig config;

  MatchUpdate _current = const MatchUpdate();
  String? _pendingReference;
  int _pendingWindows = 0;

  MatchUpdate get current => _current;

  MatchUpdate? update(List<MatchCandidate> candidates) {
    final eligible =
        candidates
            .where(
              (candidate) =>
                  candidate.explicitReference ||
                  candidate.score >= config.possibleThreshold,
            )
            .toList(growable: false)
          ..sort(_compareCandidates);
    if (eligible.isEmpty) {
      _clearPending();
      return null;
    }

    final best = eligible.first;
    if (!_confirmed(best)) return null;
    final displayed = _current.featured;
    if (!_canReplace(displayed, best)) return null;

    final featured = displayed != null && _samePassage(displayed, best)
        ? (best.score > displayed.score ? best : displayed)
        : best;
    final alternatives = _alternatives(eligible, featured);
    final next = MatchUpdate(featured: featured, alternatives: alternatives);
    if (_sameUpdate(_current, next)) return null;
    _current = next;
    return next;
  }

  bool _confirmed(MatchCandidate candidate) {
    if (candidate.explicitReference ||
        candidate.score >= config.strongThreshold) {
      _clearPending();
      return true;
    }
    final key = _referenceKey(candidate.passage.reference);
    if (_pendingReference == key) {
      _pendingWindows++;
    } else {
      _pendingReference = key;
      _pendingWindows = 1;
    }
    if (_pendingWindows < config.confirmationWindows) return false;
    _clearPending();
    return true;
  }

  bool _canReplace(MatchCandidate? displayed, MatchCandidate candidate) {
    if (displayed == null || _samePassage(displayed, candidate)) return true;
    if (candidate.explicitReference) return true;
    if (displayed.explicitReference) return false;
    return candidate.score >= displayed.score + config.replacementMargin;
  }

  List<MatchCandidate> _alternatives(
    List<MatchCandidate> candidates,
    MatchCandidate featured,
  ) {
    final seen = <String>{_referenceKey(featured.passage.reference)};
    final alternatives = <MatchCandidate>[];
    for (final candidate in candidates) {
      final key = _referenceKey(candidate.passage.reference);
      if (seen.add(key)) alternatives.add(candidate);
      if (alternatives.length == 3) break;
    }
    return List.unmodifiable(alternatives);
  }

  void _clearPending() {
    _pendingReference = null;
    _pendingWindows = 0;
  }
}

int _compareCandidates(MatchCandidate left, MatchCandidate right) {
  if (left.explicitReference != right.explicitReference) {
    return left.explicitReference ? -1 : 1;
  }
  final score = right.score.compareTo(left.score);
  return score != 0 ? score : left.passage.label.compareTo(right.passage.label);
}

bool _samePassage(MatchCandidate left, MatchCandidate right) =>
    _referenceKey(left.passage.reference) ==
    _referenceKey(right.passage.reference);

bool _sameUpdate(MatchUpdate left, MatchUpdate right) {
  if (left.featured == null || right.featured == null) {
    return left.featured == null && right.featured == null;
  }
  if (!_sameCandidate(left.featured!, right.featured!)) return false;
  if (left.alternatives.length != right.alternatives.length) return false;
  for (var index = 0; index < left.alternatives.length; index++) {
    if (!_sameCandidate(left.alternatives[index], right.alternatives[index])) {
      return false;
    }
  }
  return true;
}

bool _sameCandidate(MatchCandidate left, MatchCandidate right) =>
    _samePassage(left, right) &&
    left.score == right.score &&
    left.band == right.band &&
    left.explicitReference == right.explicitReference;

String _referenceKey(ScriptureReference reference) =>
    '${reference.book}:${reference.chapter}:'
    '${reference.startVerse}:${reference.endVerse}';
