import 'dart:io';

import 'bibles/builder.dart';

Future<void> main(List<String> arguments) async {
  final outputIndex = arguments.indexOf('--output');
  if (outputIndex < 0 || outputIndex == arguments.length - 1) {
    stderr.writeln(
      'Usage: dart run tool/build_bibles.dart <source...> --output <database>',
    );
    exitCode = 64;
    return;
  }
  final output = arguments[outputIndex + 1];
  final inputs = arguments.sublist(0, outputIndex);
  if (inputs.isEmpty || outputIndex + 2 != arguments.length) {
    stderr.writeln(
      'Usage: dart run tool/build_bibles.dart <source...> --output <database>',
    );
    exitCode = 64;
    return;
  }

  try {
    final result = await BibleBuilder().build(
      inputs.map(File.new).toList(growable: false),
      output,
    );
    for (final translation in result.translations) {
      stdout.writeln(
        '${translation.name}: ${translation.passageCount} passages',
      );
    }
    stdout.writeln(
      '${result.translations.length} translations, '
      '${result.passageCount} passages',
    );
    stdout.writeln('Output: ${result.outputPath}');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  }
}
