import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guide/app.dart';

void main() {
  testWidgets('renders the application shell', (tester) async {
    await tester.pumpWidget(const ScriptureListenerApp(home: Text('Ready')));

    expect(find.text('Scripture Listener'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });
}
