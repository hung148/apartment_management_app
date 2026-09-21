import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_localizations.dart';

/// Full-width totals with fixed, reachable actions and scrollable large values.
class CompactSummaryToolbar extends StatelessWidget {
  const CompactSummaryToolbar({
    super.key,
    required this.values,
    required this.labels,
    required this.icons,
    required this.searchController,
    required this.searchTitle,
    required this.searchHint,
    required this.addLabel,
    required this.addIcon,
    required this.actionKeyPrefix,
    this.onAdd,
  });
  final List<String> values;
  final List<String> labels;
  final List<IconData> icons;
  final TextEditingController searchController;
  final String searchTitle, searchHint, addLabel, actionKeyPrefix;
  final IconData addIcon;
  final VoidCallback? onAdd;

  Future<void> _search(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) {
      final t = AppTranslations.of(context);
      return AlertDialog(
        title: Text(searchTitle),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => Navigator.pop(context),
            decoration: InputDecoration(
              labelText: searchTitle,
              helperText: searchHint,
              helperMaxLines: 4,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: searchController.clear,
            child: Text(t['tenant_clear_search']),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t['close']),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final baseStyle = DefaultTextStyle.of(context).style;
    final valueStyle = baseStyle.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    final labelStyle = baseStyle.copyWith(fontSize: 13);
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640 * scaler.scale(14) / 14;
        final minimumCardWidth = List.generate(
          values.length,
          (i) =>
              (compact ? 12 : 24) +
              20 +
              textWidth(values[i], valueStyle) +
              (compact ? 0 : 6 + textWidth(labels[i], labelStyle)),
        ).reduce(math.max).ceilToDouble();
        return Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, available) {
                  final width = math.max(
                    minimumCardWidth,
                    (available.maxWidth - (values.length - 1) * 4) /
                        values.length,
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < values.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Tooltip(
                            message: '${labels[i]}: ${values[i]}',
                            child: Semantics(
                              label: '${labels[i]}: ${values[i]}',
                              excludeSemantics: true,
                              child: Container(
                                key: ValueKey('$actionKeyPrefix-stat-$i'),
                                width: width,
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 6 : 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      icons[i],
                                      size: 16,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(values[i], style: valueStyle),
                                    if (!compact) ...[
                                      const SizedBox(width: 6),
                                      Text(labels[i], style: labelStyle),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 4),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) => IconButton(
                key: ValueKey('$actionKeyPrefix-search'),
                tooltip: value.text.isEmpty
                    ? searchTitle
                    : '$searchTitle: ${value.text}',
                onPressed: () => _search(context),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Badge(
                  isLabelVisible: value.text.trim().isNotEmpty,
                  child: const Icon(Icons.search),
                ),
              ),
            ),
            if (onAdd != null) ...[
              const SizedBox(width: 4),
              if (compact)
                IconButton.filledTonal(
                  key: ValueKey('$actionKeyPrefix-add'),
                  tooltip: addLabel,
                  onPressed: onAdd,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(addIcon),
                )
              else
                FilledButton.tonalIcon(
                  key: ValueKey('$actionKeyPrefix-add'),
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  icon: Icon(addIcon),
                  label: Text(addLabel),
                ),
            ],
          ],
        );
      },
    );
  }
}
