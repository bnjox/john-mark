import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const corpusManifestFormatVersion = 1;
const corpusSchemaVersion = 3;
const corpusFingerprintContract = 1;

class CorpusManifest {
  const CorpusManifest({
    required this.assetId,
    required this.databaseBytes,
    required this.translationIds,
    required this.corpusFingerprint,
  });

  factory CorpusManifest.parse(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        value['formatVersion'] != corpusManifestFormatVersion ||
        value['schemaVersion'] != corpusSchemaVersion ||
        value['fingerprintContract'] != corpusFingerprintContract ||
        value['assetId'] is! String ||
        !_isSha256(value['assetId'] as String) ||
        value['databaseBytes'] is! int ||
        (value['databaseBytes'] as int) <= 0 ||
        value['corpusFingerprint'] is! String ||
        !_isSha256(value['corpusFingerprint'] as String)) {
      throw const FormatException('Invalid Bible corpus manifest');
    }
    final translations = value['translationIds'];
    if (translations is! List ||
        translations.isEmpty ||
        translations.any((item) => item is! String || item.isEmpty)) {
      throw const FormatException('Invalid Bible corpus manifest translations');
    }
    final ids = translations.cast<String>();
    if (ids.toSet().length != ids.length || !_isSorted(ids)) {
      throw const FormatException('Invalid Bible corpus manifest translations');
    }
    return CorpusManifest(
      assetId: value['assetId'] as String,
      databaseBytes: value['databaseBytes'] as int,
      translationIds: List.unmodifiable(ids),
      corpusFingerprint: value['corpusFingerprint'] as String,
    );
  }

  final String assetId;
  final int databaseBytes;
  final List<String> translationIds;
  final String corpusFingerprint;

  String encode() => jsonEncode({
    'formatVersion': corpusManifestFormatVersion,
    'schemaVersion': corpusSchemaVersion,
    'assetId': assetId,
    'databaseBytes': databaseBytes,
    'translationIds': translationIds,
    'fingerprintContract': corpusFingerprintContract,
    'corpusFingerprint': corpusFingerprint,
  });
}

class CorpusFingerprintVerse {
  const CorpusFingerprintVerse({
    required this.translationId,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final String translationId;
  final int book;
  final int chapter;
  final int verse;
  final String text;
}

String fingerprintCorpus(Iterable<CorpusFingerprintVerse> values) {
  final verses = values.toList(growable: false)
    ..sort((left, right) {
      var order = left.translationId.compareTo(right.translationId);
      if (order == 0) order = left.book.compareTo(right.book);
      if (order == 0) order = left.chapter.compareTo(right.chapter);
      if (order == 0) order = left.verse.compareTo(right.verse);
      return order;
    });
  final bytes = BytesBuilder(copy: false)
    ..add(_lengthPrefixed('$corpusFingerprintContract'));
  for (final verse in verses) {
    for (final field in [
      verse.translationId,
      verse.book,
      verse.chapter,
      verse.verse,
      verse.verse,
      verse.text,
    ]) {
      bytes.add(_lengthPrefixed('$field'));
    }
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

Uint8List _lengthPrefixed(String value) {
  final valueBytes = utf8.encode(value);
  final result = Uint8List(4 + valueBytes.length);
  ByteData.sublistView(result).setUint32(0, valueBytes.length, Endian.little);
  result.setRange(4, result.length, valueBytes);
  return result;
}

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isSorted(List<String> values) {
  for (var index = 1; index < values.length; index++) {
    if (values[index - 1].compareTo(values[index]) >= 0) return false;
  }
  return true;
}
