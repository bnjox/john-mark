import '../../core/models.dart';
import '../bible/bible_repository.dart';
import 'normalizer.dart';

class QuoteMatcher {
  QuoteMatcher(
    this._repository, {
    this.strongThreshold = 0.78,
    this.possibleThreshold = 0.68,
  });

  static const maxSignificantTokens = 12;
  static const maxCandidates = 40;

  final BibleRepository _repository;
  final double strongThreshold;
  final double possibleThreshold;

  Future<List<MatchCandidate>> match(String text, String translationId) async {
    final query = significantTokens(text, limit: maxSignificantTokens);
    if (query.length < 4) return const [];

    final passages = await _repository.quoteCandidates(
      translationId,
      query,
      limit: maxCandidates,
    );
    final matches = <MatchCandidate>[];
    for (final passage in passages.take(maxCandidates)) {
      final candidateTokens = significantTokens(passage.text);
      if (candidateTokens.length < 4) continue;
      final score = _bestScore(query, candidateTokens);
      if (score < possibleThreshold) continue;
      matches.add(
        MatchCandidate(
          passage: passage,
          score: score,
          band: score >= strongThreshold
              ? ConfidenceBand.high
              : ConfidenceBand.possible,
          explicitReference: false,
        ),
      );
    }
    matches.sort((left, right) {
      final score = right.score.compareTo(left.score);
      return score != 0
          ? score
          : left.passage.label.compareTo(right.passage.label);
    });
    return matches;
  }
}

double _bestScore(List<String> query, List<String> candidate) {
  if (candidate.length <= QuoteMatcher.maxSignificantTokens) {
    return _score(query, candidate);
  }

  var best = 0.0;
  const width = QuoteMatcher.maxSignificantTokens;
  for (var start = 0; start + width <= candidate.length; start++) {
    final score = _score(query, candidate.sublist(start, start + width));
    if (score > best) best = score;
  }
  return best;
}

double _score(List<String> query, List<String> candidate) {
  final lcs = _longestCommonSubsequence(query, candidate);
  final querySet = query.toSet();
  final candidateSet = candidate.toSet();
  final intersection = querySet.intersection(candidateSet).length;
  final union = querySet.union(candidateSet).length;

  final orderedCoverage = lcs / candidate.length;
  final tokenJaccard = union == 0 ? 0.0 : intersection / union;
  final queryCoverage = lcs / query.length;
  return (orderedCoverage * 0.55 + tokenJaccard * 0.30 + queryCoverage * 0.15)
      .clamp(0.0, 1.0);
}

int _longestCommonSubsequence(List<String> left, List<String> right) {
  var previous = List<int>.filled(right.length + 1, 0);
  for (final leftToken in left) {
    final current = List<int>.filled(right.length + 1, 0);
    for (var index = 1; index <= right.length; index++) {
      current[index] = leftToken == right[index - 1]
          ? previous[index - 1] + 1
          : max(previous[index], current[index - 1]);
    }
    previous = current;
  }
  return previous.last;
}

int max(int left, int right) => left > right ? left : right;
