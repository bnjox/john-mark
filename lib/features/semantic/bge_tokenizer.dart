import 'dart:typed_data';

import 'package:flutter/services.dart';

class BgeInputs {
  const BgeInputs({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
  });

  final Int64List inputIds;
  final Int64List attentionMask;
  final Int64List tokenTypeIds;
}

class BgeTokenizer {
  BgeTokenizer._(this._vocabulary)
    : _unknownId = _requiredToken(_vocabulary, '[UNK]'),
      _classificationId = _requiredToken(_vocabulary, '[CLS]'),
      _separatorId = _requiredToken(_vocabulary, '[SEP]');

  factory BgeTokenizer.fromVocabulary(String vocabulary) {
    final tokens = vocabulary
        .split(RegExp(r'\r?\n'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final entries = <String, int>{};
    for (var index = 0; index < tokens.length; index++) {
      entries.putIfAbsent(tokens[index], () => index);
    }
    return BgeTokenizer._(Map.unmodifiable(entries));
  }

  static Future<BgeTokenizer> fromAsset(
    String assetPath, {
    AssetBundle? bundle,
  }) async => BgeTokenizer.fromVocabulary(
    await (bundle ?? rootBundle).loadString(assetPath),
  );

  final Map<String, int> _vocabulary;
  final int _unknownId;
  final int _classificationId;
  final int _separatorId;

  BgeInputs encode(String text, {int maxLength = 512}) {
    if (maxLength < 2 || maxLength > 512) {
      throw RangeError.range(maxLength, 2, 512, 'maxLength');
    }
    final pieces = <int>[];
    for (final token in _basicTokens(text)) {
      pieces.addAll(_wordPieces(token));
      if (pieces.length >= maxLength - 2) break;
    }

    final inputIds = Int64List(maxLength);
    final attentionMask = Int64List(maxLength);
    final tokenTypeIds = Int64List(maxLength);
    final contentLength = pieces.length.clamp(0, maxLength - 2);
    inputIds[0] = _classificationId;
    for (var index = 0; index < contentLength; index++) {
      inputIds[index + 1] = pieces[index];
    }
    inputIds[contentLength + 1] = _separatorId;
    attentionMask.fillRange(0, contentLength + 2, 1);
    return BgeInputs(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: tokenTypeIds,
    );
  }

  Iterable<int> _wordPieces(String token) sync* {
    if (_vocabulary[token] case final exact?) {
      yield exact;
      return;
    }
    final pieces = <int>[];
    var start = 0;
    while (start < token.length) {
      int? match;
      var end = token.length;
      while (end > start) {
        final candidate =
            '${start == 0 ? '' : '##'}${token.substring(start, end)}';
        if (_vocabulary[candidate] case final id?) {
          match = id;
          break;
        }
        end--;
      }
      if (match == null) {
        yield _unknownId;
        return;
      }
      pieces.add(match);
      start = end;
    }
    yield* pieces;
  }
}

List<String> _basicTokens(String text) {
  final normalized = _stripAccents(text.toLowerCase());
  return RegExp(r'[\p{L}\p{N}]+|[^\p{L}\p{N}\s]', unicode: true)
      .allMatches(normalized)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}

String _stripAccents(String value) {
  const replacements = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
  };
  return value
      .split('')
      .map((character) => replacements[character] ?? character)
      .join();
}

int _requiredToken(Map<String, int> vocabulary, String token) {
  final id = vocabulary[token];
  if (id == null) throw FormatException('Vocabulary is missing $token');
  return id;
}
