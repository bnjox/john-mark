import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/features/semantic/bge_tokenizer.dart';

void main() {
  final tokenizer = BgeTokenizer.fromVocabulary('''
[PAD]
[UNK]
[CLS]
[SEP]
[MASK]
loved
world
##s
!
cafe
''');

  test('encodes lowercase punctuation and WordPiece continuation', () {
    final inputs = tokenizer.encode('Loved worlds!');

    expect(inputs.inputIds.take(6), [2, 5, 6, 7, 8, 3]);
    expect(inputs.attentionMask.take(6), everyElement(1));
    expect(inputs.attentionMask.skip(6), everyElement(0));
    expect(inputs.tokenTypeIds, everyElement(0));
  });

  test('normalizes accents and replaces unknown tokens once', () {
    final inputs = tokenizer.encode('CAFÉ mystery');

    expect(inputs.inputIds.take(4), [2, 9, 1, 3]);
  });

  test('truncates content while preserving separator and padding', () {
    final inputs = tokenizer.encode('loved loved loved loved', maxLength: 5);

    expect(inputs.inputIds, [2, 5, 5, 5, 3]);
    expect(inputs.attentionMask, everyElement(1));
  });

  test('rejects invalid sequence lengths and vocabularies', () {
    expect(() => tokenizer.encode('loved', maxLength: 1), throwsRangeError);
    expect(
      () => BgeTokenizer.fromVocabulary('[PAD]\n[UNK]\n[CLS]'),
      throwsFormatException,
    );
  });
}
