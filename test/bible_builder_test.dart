import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../tool/bibles/builder.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'bible_builder_',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  Future<File> writeJson(String name, Object value) async {
    final file = File('${temporaryDirectory.path}/$name');
    final encoded = name.endsWith('.fsb') ? ['test-document-id', value] : value;
    await file.writeAsString(jsonEncode(encoded));
    return file;
  }

  test(
    'builds deterministic translations, passages, and lexical tokens',
    () async {
      final output = '${temporaryDirectory.path}/bibles.db';
      final result = await BibleBuilder().build([
        File('test/fixtures/bibles/minimal.fsb'),
        File('test/fixtures/bibles/minimal-zefania.xml'),
      ], output);

      expect(result.translations.map((translation) => translation.id), [
        'fictional-fsb',
        'fictional-xml',
      ]);
      expect(result.passageCount, greaterThan(6));

      final database = sqlite3.open(output, mode: OpenMode.readOnly);
      addTearDown(database.close);
      expect(database.userVersion, 1);
      expect(database.select('SELECT id, name FROM translations ORDER BY id'), [
        {'id': 'fictional-fsb', 'name': 'Fictional FSB'},
        {'id': 'fictional-xml', 'name': 'Fictional XML'},
      ]);
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM passages')
            .first['count'],
        12,
      );
      expect(
        database.select(
          'SELECT label, display_text FROM passages '
          'WHERE translation_id = ? AND start_verse = 15 AND end_verse = 17',
          ['fictional-fsb'],
        ).single,
        {
          'label': 'John 3:15–17',
          'display_text':
              'Everyone who trusts the promised light may share lasting life. '
              'The Maker cherished the world and offered the beloved Son. '
              'The Son came to restore the world, not to condemn it.',
        },
      );
      expect(
        database.select(
          'SELECT COUNT(*) AS count FROM passage_tokens WHERE token = ?',
          ['world'],
        ).first['count'],
        greaterThan(0),
      );

      final secondOutput = '${temporaryDirectory.path}/second.db';
      await BibleBuilder().build([
        File('test/fixtures/bibles/minimal.fsb'),
        File('test/fixtures/bibles/minimal-zefania.xml'),
      ], secondOutput);
      expect(
        await File(secondOutput).readAsBytes(),
        await File(output).readAsBytes(),
      );
    },
  );

  test('rejects a non-canonical FSB book with source location', () async {
    final source = await writeJson('bad-book.fsb', {
      'name': 'Bad Book',
      'books': [
        {
          'number': 99,
          'name': 'Unknown',
          'chapters': [
            {
              'number': 1,
              'verses': [
                {'number': 1, 'text': 'Fictional text'},
              ],
            },
          ],
        },
      ],
    });

    await expectLater(
      BibleBuilder().build([source], '${temporaryDirectory.path}/bad.db'),
      throwsA(
        isA<FormatException>()
            .having((error) => error.message, 'message', contains(source.path))
            .having(
              (error) => error.message,
              'message',
              contains(r'$[1].books[0].number'),
            ),
      ),
    );
  });

  test('accepts FreeShow string numbering and omitted verse slots', () async {
    final source = await writeJson('real-shape.fsb', {
      'name': 'Real Shape',
      'copyright': '',
      'version': '1',
      'metadata': <String, Object>{},
      'id': 'bible-id',
      'bookId': 43,
      'book': 'John',
      'chapter': '3',
      'verses': <String, Object>{},
      'activeVerses': <Object>[],
      'books': [
        {
          'number': '43',
          'name': 'John',
          'chapters': [
            {
              'number': '3',
              'verses': [
                {'number': '15', 'text': 'Kept verse.'},
                {'number': '16', 'text': ''},
                {'number': '17', 'text': 'Another kept verse.'},
              ],
            },
          ],
        },
      ],
    });
    final output = '${temporaryDirectory.path}/real-shape.db';

    await BibleBuilder().build([source], output);

    final database = sqlite3.open(output, mode: OpenMode.readOnly);
    addTearDown(database.close);
    expect(
      database
          .select('SELECT start_verse FROM passages ORDER BY start_verse')
          .map((row) => row['start_verse']),
      [15, 17],
    );
  });

  test(
    'rejects missing FSB verse text without replacing existing output',
    () async {
      final source = await writeJson('missing-text.fsb', {
        'name': 'Missing Text',
        'books': [
          {
            'number': 43,
            'name': 'John',
            'chapters': [
              {
                'number': 3,
                'verses': [
                  {'number': 16},
                ],
              },
            ],
          },
        ],
      });
      final output = File('${temporaryDirectory.path}/existing.db');
      await output.writeAsString('keep me');

      await expectLater(
        BibleBuilder().build([source], output.path),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                contains(source.path),
              )
              .having(
                (error) => error.message,
                'message',
                contains(r'$[1].books[0].chapters[0].verses[0].text'),
              ),
        ),
      );
      expect(await output.readAsString(), 'keep me');
    },
  );

  test('rejects unsupported XML root with its element location', () async {
    final source = File('${temporaryDirectory.path}/bad.xml');
    await source.writeAsString('<NOT_A_BIBLE />');

    await expectLater(
      BibleBuilder().build([source], '${temporaryDirectory.path}/bad.db'),
      throwsA(
        isA<FormatException>()
            .having((error) => error.message, 'message', contains(source.path))
            .having(
              (error) => error.message,
              'message',
              contains('/NOT_A_BIBLE'),
            ),
      ),
    );
  });

  test('rejects unknown FSB keys with their JSON location', () async {
    final source = await writeJson('unknown-key.fsb', {
      ..._singleVerseBible('Unknown Key'),
      'unexpected': 'must not be ignored',
    });

    await expectLater(
      BibleBuilder().build([source], '${temporaryDirectory.path}/bad.db'),
      throwsA(
        isA<FormatException>()
            .having((error) => error.message, 'message', contains(source.path))
            .having(
              (error) => error.message,
              'message',
              contains(r'$[1].unexpected'),
            ),
      ),
    );
  });

  test('rejects unknown XML children and attributes with locations', () async {
    final cases = <(String, String, String)>[
      (
        'unknown-child.xml',
        '<XMLBIBLE biblename="Test"><INFORMATION />'
            '<BIBLEBOOK bnumber="43" bname="John"><CHAPTER cnumber="1">'
            '<VERS vnumber="1">Text</VERS></CHAPTER></BIBLEBOOK></XMLBIBLE>',
        '/XMLBIBLE/INFORMATION',
      ),
      (
        'unknown-attribute.xml',
        '<XMLBIBLE biblename="Test"><BIBLEBOOK bnumber="43" bname="John">'
            '<CHAPTER cnumber="1"><VERS vnumber="1" style="ignored">'
            'Text</VERS></CHAPTER></BIBLEBOOK></XMLBIBLE>',
        '/XMLBIBLE/BIBLEBOOK[1]/CHAPTER[1]/VERS[1]/@style',
      ),
    ];

    for (final (name, contents, location) in cases) {
      final source = File('${temporaryDirectory.path}/$name');
      await source.writeAsString(contents);
      await expectLater(
        BibleBuilder().build([source], '${temporaryDirectory.path}/$name.db'),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                contains(source.path),
              )
              .having((error) => error.message, 'message', contains(location)),
        ),
      );
    }
  });

  test('rejects duplicate translation IDs after slugging', () async {
    final first = await writeJson('first.fsb', _singleVerseBible('Same Name'));
    final second = await writeJson(
      'second.fsb',
      _singleVerseBible('Same--Name'),
    );

    await expectLater(
      BibleBuilder().build([
        first,
        second,
      ], '${temporaryDirectory.path}/bad.db'),
      throwsA(
        isA<FormatException>()
            .having((error) => error.message, 'message', contains(second.path))
            .having(
              (error) => error.message,
              'message',
              contains(r'$[1].name'),
            ),
      ),
    );
  });

  test('rejects unsupported source extensions', () async {
    final source = File('${temporaryDirectory.path}/bible.txt');
    await source.writeAsString('not supported');

    await expectLater(
      BibleBuilder().build([source], '${temporaryDirectory.path}/bad.db'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(source.path),
        ),
      ),
    );
  });

  test('strictly rejects invalid FSB numbering, ranges, and text', () async {
    final cases = <(String, Map<String, Object>, String)>[
      (
        'duplicate-book',
        {
          ..._singleVerseBible('Duplicate Book'),
          'books': [
            ...(_singleVerseBible('unused')['books']! as List<Object>),
            ...(_singleVerseBible('unused')['books']! as List<Object>),
          ],
        },
        r'$[1].books[1].number',
      ),
      (
        'duplicate-chapter',
        _bibleWithChapters('Duplicate Chapter', [
          _chapter(1, [_verse(1)]),
          _chapter(1, [_verse(2)]),
        ]),
        r'$[1].books[0].chapters[1].number',
      ),
      (
        'duplicate-verse',
        _bibleWithChapters('Duplicate Verse', [
          _chapter(1, [_verse(1), _verse(1)]),
        ]),
        r'$[1].books[0].chapters[0].verses[1].number',
      ),
      (
        'non-positive',
        _bibleWithChapters('Non Positive', [
          _chapter(0, [_verse(1)]),
        ]),
        r'$[1].books[0].chapters[0].number',
      ),
      (
        'reversed-range',
        _bibleWithChapters('Reversed Range', [
          _chapter(1, [_verse(4, endNumber: 3)]),
        ]),
        r'$[1].books[0].chapters[0].verses[0].endNumber',
      ),
    ];

    for (final (name, bible, location) in cases) {
      final source = await writeJson('$name.fsb', bible);
      await expectLater(
        BibleBuilder().build([source], '${temporaryDirectory.path}/$name.db'),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                contains(source.path),
              )
              .having((error) => error.message, 'message', contains(location)),
        ),
        reason: name,
      );
    }
  });
}

Map<String, Object> _singleVerseBible(String name) => {
  'name': name,
  'books': [
    {
      'number': 43,
      'name': 'John',
      'chapters': [
        {
          'number': 1,
          'verses': [
            {'number': 1, 'text': 'Entirely fictional source wording.'},
          ],
        },
      ],
    },
  ],
};

Map<String, Object> _bibleWithChapters(
  String name,
  List<Map<String, Object>> chapters,
) => {
  'name': name,
  'books': [
    {'number': 43, 'name': 'John', 'chapters': chapters},
  ],
};

Map<String, Object> _chapter(int number, List<Map<String, Object>> verses) => {
  'number': number,
  'verses': verses,
};

Map<String, Object> _verse(
  int number, {
  int? endNumber,
  String text = 'Entirely fictional source wording.',
}) => {'number': number, 'endNumber': ?endNumber, 'text': text};
