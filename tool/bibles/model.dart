class SourceBible {
  const SourceBible({
    required this.sourcePath,
    required this.name,
    required this.books,
  });

  final String sourcePath;
  final String name;
  final List<SourceBook> books;
}

class SourceBook {
  const SourceBook({
    required this.number,
    required this.name,
    required this.chapters,
  });

  final int number;
  final String name;
  final List<SourceChapter> chapters;
}

class SourceChapter {
  const SourceChapter({required this.number, required this.verses});

  final int number;
  final List<SourceVerse> verses;
}

class SourceVerse {
  const SourceVerse({
    required this.number,
    required this.endNumber,
    required this.text,
  });

  final int number;
  final int endNumber;
  final String text;
}
