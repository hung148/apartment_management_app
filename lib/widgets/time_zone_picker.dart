import 'package:flutter/material.dart';
import '../utils/localizations/app_localizations.dart';
import '../utils/time_zone_choices.dart';
import 'app_dialog.dart';

Future<String?> chooseTimeZone(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TimeZonePicker(current: current),
    );

class _TimeZonePicker extends StatefulWidget {
  final String current;
  const _TimeZonePicker({required this.current});
  @override
  State<_TimeZonePicker> createState() => _TimeZonePickerState();
}

class _TimeZonePickerState extends State<_TimeZonePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final zones =
        {if (widget.current.isNotEmpty) widget.current, ...timeZoneChoices}
            .where(
              (zone) => zone
                  .replaceAll('_', ' ')
                  .toLowerCase()
                  .contains(_query.trim().replaceAll('_', ' ').toLowerCase()),
            )
            .toList();
    return AppDialog(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t['timezone_choose'],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: t['close'],
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(t['timezone_search']),
                const SizedBox(height: 8),
                Semantics(
                  label: t['timezone_search'],
                  child: TextField(
                    key: const ValueKey('timezone-search'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const SizedBox(height: 12),
                if (zones.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t['timezone_no_results']),
                  ),
                for (final zone in zones)
                  InkWell(
                    onTap: () => Navigator.pop(context, zone),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(zone)),
                          if (zone == widget.current) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
