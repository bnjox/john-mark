import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../bible/bible_repository.dart';

class PassageSheet extends StatefulWidget {
  const PassageSheet({
    required this.repository,
    required this.translationId,
    required this.passage,
    super.key,
  });

  final BibleRepository repository;
  final String translationId;
  final Passage passage;

  @override
  State<PassageSheet> createState() => _PassageSheetState();
}

class _PassageSheetState extends State<PassageSheet> {
  late Future<Passage?> _context;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void didUpdateWidget(covariant PassageSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.translationId != widget.translationId ||
        oldWidget.passage.reference != widget.passage.reference) {
      _loadContext();
    }
  }

  void _loadContext() {
    _context = widget.repository.context(
      widget.translationId,
      widget.passage.reference,
      before: 1,
      after: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Semantics(
        container: true,
        label: 'Passage context',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: FutureBuilder<Passage?>(
            future: _context,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final contextPassage = snapshot.data ?? widget.passage;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      contextPassage.label,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      contextPassage.text,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
