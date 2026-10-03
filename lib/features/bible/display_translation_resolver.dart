import '../../core/models.dart';

Translation resolveDisplayTranslation(List<Translation> translations) {
  if (translations.isEmpty) {
    throw StateError('No Bible translations are available');
  }

  for (final translation in translations) {
    if (_normalize(translation.id) == 'nkjv') return translation;
  }
  for (final translation in translations) {
    if (_normalize(translation.name) == 'new king james version') {
      return translation;
    }
  }

  final ordered = [...translations]
    ..sort((left, right) {
      final id = _normalize(left.id).compareTo(_normalize(right.id));
      if (id != 0) return id;
      final name = _normalize(left.name).compareTo(_normalize(right.name));
      if (name != 0) return name;
      final exactId = left.id.compareTo(right.id);
      return exactId != 0 ? exactId : left.name.compareTo(right.name);
    });
  return ordered.first;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
