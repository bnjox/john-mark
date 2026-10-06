import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/app.dart';
import 'package:john_mark/features/startup/runtime_bootstrap_screen.dart';

void main() {
  testWidgets('renders immediately while runtime initialization is pending', (
    tester,
  ) async {
    final loading = Completer<Widget>();

    await tester.pumpWidget(
      JohnMarkApp(home: RuntimeBootstrapScreen(loadHome: () => loading.future)),
    );

    expect(find.text('John Mark'), findsOneWidget);
    expect(find.text('Preparing scripture library…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loading.complete(const Scaffold(body: Text('Ready')));
    await tester.pump();
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('offers a retry after startup fails', (tester) async {
    var attempts = 0;

    await tester.pumpWidget(
      JohnMarkApp(
        home: RuntimeBootstrapScreen(
          loadHome: () async {
            attempts++;
            if (attempts == 1) throw StateError('failed');
            return const Scaffold(body: Text('Ready'));
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Scripture library unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Ready'), findsOneWidget);
  });
}
