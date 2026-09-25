import '../../core/models.dart';
import '../bible/bible_repository.dart';
import 'match_stabilizer.dart';
import 'quote_matcher.dart';
import 'reference_parser.dart';

class ScriptureMatcher {
  ScriptureMatcher({
    required BibleRepository repository,
    required this.translationId,
    this.config = const MatchConfig(),
  }) : _referenceParser = ReferenceParser(repository),
       _quoteMatcher = QuoteMatcher(
         repository,
         strongThreshold: config.strongThreshold,
         possibleThreshold: config.possibleThreshold,
       ),
       _stabilizer = MatchStabilizer(config);

  final String translationId;
  final MatchConfig config;
  final ReferenceParser _referenceParser;
  final QuoteMatcher _quoteMatcher;
  final MatchStabilizer _stabilizer;

  MatchUpdate get current => _stabilizer.current;

  Future<MatchUpdate?> match(String finalizedText) async {
    final reference = await _referenceParser.parse(
      finalizedText,
      translationId,
    );
    if (reference != null) return _stabilizer.update([reference]);

    final quotations = await _quoteMatcher.match(finalizedText, translationId);
    return _stabilizer.update(quotations);
  }
}
