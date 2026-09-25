import 'dart:convert';
import 'dart:io';

import 'model.dart';

class FsbParser {
  Future<SourceBible> parse(File file) async {
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw FormatException('${file.path}: JSON: ${error.message}');
    }

    final root = _map(decoded, file.path, r'$');
    final name = _string(root['name'], file.path, r'$.name');
    final rawBooks = _list(root['books'], file.path, r'$.books');
    if (rawBooks.isEmpty) {
      _fail(file.path, r'$.books', 'must not be empty');
    }

    final bookNumbers = <int>{};
    final books = <SourceBook>[];
    for (var bookIndex = 0; bookIndex < rawBooks.length; bookIndex++) {
      final location =
          r'$.books['
          '$bookIndex]';
      final rawBook = _map(rawBooks[bookIndex], file.path, location);
      final number = _positiveInt(
        rawBook['number'],
        file.path,
        '$location.number',
      );
      if (number > 66) {
        _fail(file.path, '$location.number', 'must be between 1 and 66');
      }
      if (!bookNumbers.add(number)) {
        _fail(file.path, '$location.number', 'duplicates book $number');
      }
      final bookName = _string(rawBook['name'], file.path, '$location.name');
      final rawChapters = _list(
        rawBook['chapters'],
        file.path,
        '$location.chapters',
      );
      if (rawChapters.isEmpty) {
        _fail(file.path, '$location.chapters', 'must not be empty');
      }

      final chapterNumbers = <int>{};
      final chapters = <SourceChapter>[];
      for (
        var chapterIndex = 0;
        chapterIndex < rawChapters.length;
        chapterIndex++
      ) {
        final chapterLocation = '$location.chapters[$chapterIndex]';
        final rawChapter = _map(
          rawChapters[chapterIndex],
          file.path,
          chapterLocation,
        );
        final chapterNumber = _positiveInt(
          rawChapter['number'],
          file.path,
          '$chapterLocation.number',
        );
        if (!chapterNumbers.add(chapterNumber)) {
          _fail(
            file.path,
            '$chapterLocation.number',
            'duplicates chapter $chapterNumber',
          );
        }
        final rawVerses = _list(
          rawChapter['verses'],
          file.path,
          '$chapterLocation.verses',
        );
        if (rawVerses.isEmpty) {
          _fail(file.path, '$chapterLocation.verses', 'must not be empty');
        }
        chapters.add(
          SourceChapter(
            number: chapterNumber,
            verses: _parseVerses(rawVerses, file.path, chapterLocation),
          ),
        );
      }
      books.add(SourceBook(number: number, name: bookName, chapters: chapters));
    }
    return SourceBible(sourcePath: file.path, name: name, books: books);
  }

  List<SourceVerse> _parseVerses(
    List<Object?> rawVerses,
    String filePath,
    String chapterLocation,
  ) {
    final starts = <int>{};
    final verses = <SourceVerse>[];
    for (var verseIndex = 0; verseIndex < rawVerses.length; verseIndex++) {
      final location = '$chapterLocation.verses[$verseIndex]';
      final rawVerse = _map(rawVerses[verseIndex], filePath, location);
      final number = _positiveInt(
        rawVerse['number'],
        filePath,
        '$location.number',
      );
      if (!starts.add(number)) {
        _fail(filePath, '$location.number', 'duplicates verse $number');
      }
      final endNumber = rawVerse.containsKey('endNumber')
          ? _positiveInt(rawVerse['endNumber'], filePath, '$location.endNumber')
          : number;
      if (endNumber < number) {
        _fail(filePath, '$location.endNumber', 'must not precede number');
      }
      verses.add(
        SourceVerse(
          number: number,
          endNumber: endNumber,
          text: _string(rawVerse['text'], filePath, '$location.text'),
        ),
      );
    }
    return verses;
  }
}

Map<String, Object?> _map(Object? value, String file, String location) {
  if (value is! Map<String, Object?>) {
    _fail(file, location, 'must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String file, String location) {
  if (value is! List<Object?>) {
    _fail(file, location, 'must be an array');
  }
  return value;
}

int _positiveInt(Object? value, String file, String location) {
  if (value is! int || value <= 0) {
    _fail(file, location, 'must be a positive integer');
  }
  return value;
}

String _string(Object? value, String file, String location) {
  if (value is! String || value.trim().isEmpty) {
    _fail(file, location, 'must be a non-empty string');
  }
  return value.trim();
}

Never _fail(String file, String location, String problem) {
  throw FormatException('$file: $location $problem');
}
