const _smallNumbers = <String, int>{
  'zero': 0,
  'one': 1,
  'first': 1,
  'two': 2,
  'second': 2,
  'three': 3,
  'third': 3,
  'four': 4,
  'fourth': 4,
  'five': 5,
  'fifth': 5,
  'six': 6,
  'sixth': 6,
  'seven': 7,
  'seventh': 7,
  'eight': 8,
  'eighth': 8,
  'nine': 9,
  'ninth': 9,
  'ten': 10,
  'tenth': 10,
  'eleven': 11,
  'eleventh': 11,
  'twelve': 12,
  'twelfth': 12,
  'thirteen': 13,
  'thirteenth': 13,
  'fourteen': 14,
  'fourteenth': 14,
  'fifteen': 15,
  'fifteenth': 15,
  'sixteen': 16,
  'sixteenth': 16,
  'seventeen': 17,
  'seventeenth': 17,
  'eighteen': 18,
  'eighteenth': 18,
  'nineteen': 19,
  'nineteenth': 19,
};

const _tens = <String, int>{
  'twenty': 20,
  'twentieth': 20,
  'thirty': 30,
  'thirtieth': 30,
  'forty': 40,
  'fortieth': 40,
  'fifty': 50,
  'fiftieth': 50,
  'sixty': 60,
  'sixtieth': 60,
  'seventy': 70,
  'seventieth': 70,
  'eighty': 80,
  'eightieth': 80,
  'ninety': 90,
  'ninetieth': 90,
};

const _stopWords = <String>{
  'a',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'but',
  'by',
  'for',
  'from',
  'he',
  'her',
  'his',
  'i',
  'in',
  'is',
  'it',
  'its',
  'me',
  'my',
  'not',
  'of',
  'on',
  'or',
  'our',
  'she',
  'that',
  'the',
  'their',
  'them',
  'then',
  'they',
  'this',
  'to',
  'us',
  'was',
  'we',
  'were',
  'with',
  'you',
  'your',
};

String normalizeSpokenText(String text) {
  final plain = text
      .toLowerCase()
      .replaceAll(RegExp(r"[’']"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (plain.isEmpty) return '';

  final input = plain.split(RegExp(r'\s+'));
  final output = <String>[];
  for (var index = 0; index < input.length;) {
    final number = _readNumber(input, index);
    if (number == null) {
      output.add(input[index]);
      index++;
    } else {
      output.add('${number.value}');
      index = number.end;
    }
  }
  return output.join(' ');
}

List<String> normalizedTokens(String text) {
  final normalized = normalizeSpokenText(text);
  return normalized.isEmpty ? const [] : normalized.split(' ');
}

List<String> significantTokens(String text, {int? limit}) {
  final tokens = normalizedTokens(text)
      .where((token) => !_stopWords.contains(token))
      .toList(growable: false);
  if (limit == null || tokens.length <= limit) return tokens;
  return tokens.sublist(tokens.length - limit);
}

({int value, int end})? _readNumber(List<String> tokens, int start) {
  final first = tokens[start];
  if (first == 'one' && start + 1 < tokens.length) {
    final hundred = tokens[start + 1];
    if (hundred == 'hundred' || hundred == 'hundredth') {
      var end = start + 2;
      var value = 100;
      if (end < tokens.length && tokens[end] == 'and') end++;
      if (end < tokens.length) {
        final remainder = _underHundred(tokens, end);
        if (remainder != null && value + remainder.value <= 150) {
          value += remainder.value;
          end = remainder.end;
        }
      }
      return (value: value, end: end);
    }
  }
  return _underHundred(tokens, start);
}

({int value, int end})? _underHundred(List<String> tokens, int start) {
  final token = tokens[start];
  final small = _smallNumbers[token];
  if (small != null) return (value: small, end: start + 1);

  final tens = _tens[token];
  if (tens == null) return null;
  final next = start + 1;
  if (next < tokens.length) {
    final unit = _smallNumbers[tokens[next]];
    if (unit != null && unit > 0 && unit < 10) {
      return (value: tens + unit, end: next + 1);
    }
  }
  return (value: tens, end: next);
}
