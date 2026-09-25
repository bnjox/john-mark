import 'dart:io';

import 'package:xml/xml.dart';

import 'model.dart';

class ZefaniaXmlParser {
  Future<SourceBible> parse(File file) async {
    late XmlDocument document;
    try {
      document = XmlDocument.parse(await file.readAsString());
    } on XmlParserException catch (error) {
      throw FormatException('${file.path}: XML: ${error.message}');
    }

    final root = document.rootElement;
    if (root.name.local != 'XMLBIBLE') {
      _fail(file.path, '/${root.name.local}', 'unsupported root element');
    }
    final name = _attribute(root, 'biblename', file.path, '/XMLBIBLE');
    final bookElements = root.findElements('BIBLEBOOK').toList();
    if (bookElements.isEmpty) {
      _fail(file.path, '/XMLBIBLE', 'contains no BIBLEBOOK elements');
    }

    final bookNumbers = <int>{};
    final books = <SourceBook>[];
    for (var bookIndex = 0; bookIndex < bookElements.length; bookIndex++) {
      final element = bookElements[bookIndex];
      final location = '/XMLBIBLE/BIBLEBOOK[${bookIndex + 1}]';
      final number = _positiveAttribute(
        element,
        'bnumber',
        file.path,
        location,
      );
      if (number > 66) {
        _fail(file.path, '$location/@bnumber', 'must be between 1 and 66');
      }
      if (!bookNumbers.add(number)) {
        _fail(file.path, '$location/@bnumber', 'duplicates book $number');
      }
      final chapterElements = element.findElements('CHAPTER').toList();
      if (chapterElements.isEmpty) {
        _fail(file.path, location, 'contains no CHAPTER elements');
      }

      final chapterNumbers = <int>{};
      final chapters = <SourceChapter>[];
      for (
        var chapterIndex = 0;
        chapterIndex < chapterElements.length;
        chapterIndex++
      ) {
        final chapterElement = chapterElements[chapterIndex];
        final chapterLocation = '$location/CHAPTER[${chapterIndex + 1}]';
        final chapterNumber = _positiveAttribute(
          chapterElement,
          'cnumber',
          file.path,
          chapterLocation,
        );
        if (!chapterNumbers.add(chapterNumber)) {
          _fail(
            file.path,
            '$chapterLocation/@cnumber',
            'duplicates chapter $chapterNumber',
          );
        }
        final verseElements = chapterElement.findElements('VERS').toList();
        if (verseElements.isEmpty) {
          _fail(file.path, chapterLocation, 'contains no VERS elements');
        }
        final starts = <int>{};
        final verses = <SourceVerse>[];
        for (
          var verseIndex = 0;
          verseIndex < verseElements.length;
          verseIndex++
        ) {
          final verseElement = verseElements[verseIndex];
          final verseLocation = '$chapterLocation/VERS[${verseIndex + 1}]';
          final number = _positiveAttribute(
            verseElement,
            'vnumber',
            file.path,
            verseLocation,
          );
          if (!starts.add(number)) {
            _fail(
              file.path,
              '$verseLocation/@vnumber',
              'duplicates verse $number',
            );
          }
          final endNumber = verseElement.getAttribute('endNumber') == null
              ? number
              : _positiveAttribute(
                  verseElement,
                  'endNumber',
                  file.path,
                  verseLocation,
                );
          if (endNumber < number) {
            _fail(
              file.path,
              '$verseLocation/@endNumber',
              'must not precede vnumber',
            );
          }
          final text = verseElement.innerText.trim();
          if (text.isEmpty) {
            _fail(file.path, verseLocation, 'must contain text');
          }
          verses.add(
            SourceVerse(
              number: number,
              endNumber: endNumber,
              text: text.replaceAll(RegExp(r'\s+'), ' '),
            ),
          );
        }
        chapters.add(SourceChapter(number: chapterNumber, verses: verses));
      }
      books.add(
        SourceBook(
          number: number,
          name: _attribute(element, 'bname', file.path, location),
          chapters: chapters,
        ),
      );
    }
    return SourceBible(sourcePath: file.path, name: name, books: books);
  }
}

String _attribute(
  XmlElement element,
  String name,
  String file,
  String location,
) {
  final value = element.getAttribute(name)?.trim();
  if (value == null || value.isEmpty) {
    _fail(file, '$location/@$name', 'must be present and non-empty');
  }
  return value;
}

int _positiveAttribute(
  XmlElement element,
  String name,
  String file,
  String location,
) {
  final value = _attribute(element, name, file, location);
  final number = int.tryParse(value);
  if (number == null || number <= 0) {
    _fail(file, '$location/@$name', 'must be a positive integer');
  }
  return number;
}

Never _fail(String file, String location, String problem) {
  throw FormatException('$file: $location $problem');
}
