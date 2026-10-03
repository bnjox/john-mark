import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'bge_tokenizer.dart';

abstract interface class TextEmbedder {
  Future<List<double>> embed(String text);

  Future<void> dispose();
}

class OnnxTextEmbedder implements TextEmbedder {
  OnnxTextEmbedder._(this._tokenizer, this._session, this.dimensions);

  static Future<OnnxTextEmbedder> load({
    required BgeTokenizer tokenizer,
    String modelAsset = 'assets/semantic/model.onnx',
    int dimensions = 768,
  }) async {
    final session = await OnnxRuntime().createSessionFromAsset(modelAsset);
    return OnnxTextEmbedder._(tokenizer, session, dimensions);
  }

  final BgeTokenizer _tokenizer;
  final OrtSession _session;
  final int dimensions;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  @override
  Future<List<double>> embed(String text) => _serialized(() async {
    if (_disposed) throw StateError('Text embedder is disposed');
    final tokenized = _tokenizer.encode(text);
    final shape = [1, tokenized.inputIds.length];
    final inputs = <String, OrtValue>{};
    Map<String, OrtValue> outputs = const {};
    try {
      inputs['input_ids'] = await OrtValue.fromList(tokenized.inputIds, shape);
      inputs['attention_mask'] = await OrtValue.fromList(
        tokenized.attentionMask,
        shape,
      );
      inputs['token_type_ids'] = await OrtValue.fromList(
        tokenized.tokenTypeIds,
        shape,
      );
      outputs = await _session.run(inputs);
      final output = outputs.values.where((value) {
        final outputShape = value.shape;
        return outputShape.length == 3 && outputShape.last == dimensions;
      }).firstOrNull;
      if (output == null) {
        throw StateError('Model did not return a compatible hidden state');
      }
      return _meanPoolAndNormalize(
        await output.asFlattenedList(),
        output.shape,
        tokenized.attentionMask,
        dimensions,
      );
    } finally {
      for (final value in inputs.values) {
        await value.dispose();
      }
      for (final value in outputs.values) {
        await value.dispose();
      }
    }
  });

  @override
  Future<void> dispose() => _serialized(() async {
    if (_disposed) return;
    _disposed = true;
    await _session.close();
  });

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then(
      (_) => _complete(operation, completer),
      onError: (_, _) => _complete(operation, completer),
    );
    return completer.future;
  }
}

Future<void> _complete<T>(
  Future<T> Function() operation,
  Completer<T> completer,
) async {
  try {
    completer.complete(await operation());
  } catch (error, stackTrace) {
    completer.completeError(error, stackTrace);
  }
}

List<double> _meanPoolAndNormalize(
  List<dynamic> values,
  List<int> shape,
  List<int> attentionMask,
  int dimensions,
) {
  if (shape.length != 3 ||
      shape.first != 1 ||
      shape[1] != attentionMask.length ||
      shape[2] != dimensions ||
      values.length != attentionMask.length * dimensions) {
    throw StateError('Model hidden state has an unexpected shape');
  }
  final pooled = List<double>.filled(dimensions, 0);
  var activeTokens = 0;
  for (var token = 0; token < attentionMask.length; token++) {
    if (attentionMask[token] == 0) continue;
    activeTokens++;
    final offset = token * dimensions;
    for (var dimension = 0; dimension < dimensions; dimension++) {
      pooled[dimension] += (values[offset + dimension] as num).toDouble();
    }
  }
  if (activeTokens == 0) throw StateError('Model input has no active tokens');
  var squaredNorm = 0.0;
  for (var dimension = 0; dimension < dimensions; dimension++) {
    pooled[dimension] /= activeTokens;
    squaredNorm += pooled[dimension] * pooled[dimension];
  }
  final norm = math.sqrt(squaredNorm);
  if (!norm.isFinite || norm == 0) {
    throw StateError('Model returned a zero or invalid embedding');
  }
  return List<double>.generate(
    dimensions,
    (dimension) => pooled[dimension] / norm,
    growable: false,
  );
}
