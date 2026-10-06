import 'package:flutter/material.dart';

typedef RuntimeHomeLoader = Future<Widget> Function();

class RuntimeBootstrapScreen extends StatefulWidget {
  const RuntimeBootstrapScreen({required this.loadHome, super.key});

  final RuntimeHomeLoader loadHome;

  @override
  State<RuntimeBootstrapScreen> createState() => _RuntimeBootstrapScreenState();
}

class _RuntimeBootstrapScreenState extends State<RuntimeBootstrapScreen> {
  Future<Widget>? _home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_load);
    });
  }

  void _load() {
    final home = Future.sync(widget.loadHome);
    home.ignore();
    _home = home;
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    if (home == null) return const _StartupScaffold();
    return FutureBuilder<Widget>(
      future: home,
      builder: (context, snapshot) {
        if (snapshot.hasData) return snapshot.data!;
        return _StartupScaffold(
          failure: snapshot.hasError,
          onRetry: () => setState(_load),
        );
      },
    );
  }
}

class _StartupScaffold extends StatelessWidget {
  const _StartupScaffold({this.failure = false, this.onRetry});

  final bool failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('John Mark')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: failure
                ? _StartupFailure(onRetry: onRetry!)
                : const _StartupProgress(),
          ),
        ),
      ),
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
