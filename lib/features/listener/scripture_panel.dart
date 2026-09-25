import 'package:flutter/material.dart';

import '../../core/models.dart';

class ScripturePanel extends StatelessWidget {
  const ScripturePanel({
    required this.featured,
    required this.alternatives,
    required this.isStale,
    required this.onFeaturedTap,
    required this.onAlternativeTap,
    super.key,
  });

  final MatchCandidate? featured;
  final List<MatchCandidate> alternatives;
  final bool isStale;
  final VoidCallback? onFeaturedTap;
  final ValueChanged<MatchCandidate> onAlternativeTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Detected scripture',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Detected scripture'),
          const SizedBox(height: 12),
          if (featured == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Listening for scripture…',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Open context for ${featured!.passage.label}',
              child: Material(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onFeaturedTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              Text(
                                featured!.passage.label,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              _ConfidenceLabel(
                                band: featured!.band,
                                stale: isStale,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            featured!.passage.text,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(height: 1.45),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tap to view surrounding context',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: 28),
            const _SectionLabel('Other possibilities'),
            const SizedBox(height: 8),
            ...alternatives
                .take(3)
                .map(
                  (candidate) => _AlternativeTile(
                    candidate: candidate,
                    onTap: () => onAlternativeTap(candidate),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _AlternativeTile extends StatelessWidget {
  const _AlternativeTile({required this.candidate, required this.onTap});

  final MatchCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Promote ${candidate.passage.label}',
      child: ListTile(
        minTileHeight: 56,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(candidate.passage.label),
        subtitle: Text(candidate.passage.text),
        trailing: Text(
          _confidenceText(candidate.band),
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: colors.primary),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ConfidenceLabel extends StatelessWidget {
  const _ConfidenceLabel({required this.band, required this.stale});

  final ConfidenceBand band;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final confidence = _confidenceText(band);
    final text = stale ? 'Stale · $confidence' : 'Current · $confidence';
    return Semantics(
      label: stale
          ? 'Result stale, confidence $confidence'
          : 'Result current, confidence $confidence',
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  );
}

String _confidenceText(ConfidenceBand band) => switch (band) {
  ConfidenceBand.high => 'High',
  ConfidenceBand.possible => 'Possible',
};
