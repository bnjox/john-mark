import 'package:flutter/material.dart';

typedef RuntimeHomeLoader = Future<Widget> Function();

class RuntimeBootstrapScreen extends StatefulWidget {
  const RuntimeBootstrapScreen({required this.loadHome, super.key});

  final RuntimeHomeLoader loadHome;

  @override
  State<RuntimeBootstrapScreen> createState() => _RuntimeBootstrapScreenState();
}

class _RuntimeBootstrapScreenState extends State<RuntimeBootstrapScreen> {
  late Future<Widget> _home;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _home = Future.sync(widget.loadHome);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _home,
      builder: (context, snapshot) {
        if (snapshot.hasData) return snapshot.data!;
        return Scaffold(
          appBar: AppBar(title: const Text('John Mark')),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: snapshot.hasError
                    ? _StartupFailure(onRetry: () => setState(_load))
                    : const _StartupProgress(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StartupProgress extends StatelessWidget {
  const _StartupProgress();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Preparing scripture library',
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Preparing scripture library…'),
        ],
      ),
    );
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Scripture library unavailable',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, size: 48),
          const SizedBox(height: 20),
          Text(
            'Scripture library unavailable',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            'The local library could not be prepared. Try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
