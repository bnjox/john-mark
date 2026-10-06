import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

Future<T> tracePerformance<T>(
  String name,
  Future<T> Function() operation,
) async {
  final stopwatch = Stopwatch()..start();
  final timeline = developer.TimelineTask(filterKey: 'john_mark.performance')
    ..start(name);
  try {
    return await operation();
  } finally {
    stopwatch.stop();
    final duration = stopwatch.elapsedMilliseconds;
    timeline.finish(arguments: {'durationMs': duration});
    developer.log('$name duration_ms=$duration', name: 'john_mark.performance');
    if (kProfileMode) {
      debugPrint('john_mark.performance $name duration_ms=$duration');
    }
  }
}

void recordPerformance(String name, Duration duration) {
  developer.log(
    '$name duration_ms=${duration.inMilliseconds}',
    name: 'john_mark.performance',
  );
  if (kProfileMode) {
    debugPrint(
      'john_mark.performance $name duration_ms=${duration.inMilliseconds}',
    );
  }
}
