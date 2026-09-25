import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScriptureListenerApp(home: Center(child: Text('Ready'))));
}
