import 'package:flutter/material.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';

/// Search only selects existing records; a query is never saved as an ID.
Future<T?> showSearchableOptions<T extends Object>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  T? selected,
}) => showDialog<T>(
  context: context,
  builder: (_) => _SearchOptionsDialog<T>(
    title: title,
    options: options,
    labelOf: labelOf,
    selected: selected,
  ),
);

class SearchableSelectField<T extends Object> extends StatelessWidget {
  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;
  final ValueChanged<T?> onChanged;
  final bool allowClear;

  const SearchableSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.allowClear = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final result = await showSearchableOptions<T>(
          context: context,
          title: label,
          options: options,
          labelOf: labelOf,
          selected: selected,
        );
        if (context.mounted && result != null) onChanged(result);
      },
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowClear && selected != null)
                IconButton(
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).deleteButtonTooltip,
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.clear),
                ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.search),
              ),
            ],
          ),
        ),
        child: Text(selected == null ? '' : labelOf(selected as T)),
      ),
    ),
  );
}

class _SearchOptionsDialog<T extends Object> extends StatefulWidget {
  final String title;
  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;
  const _SearchOptionsDialog({
    required this.title,
    required this.options,
    required this.labelOf,
    this.selected,
  });

  @override
  State<_SearchOptionsDialog<T>> createState() =>
      _SearchOptionsDialogState<T>();
}

class _SearchOptionsDialogState<T extends Object>
    extends State<_SearchOptionsDialog<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final matches = widget.options
        .where(
          (option) => widget
              .labelOf(option)
              .toLowerCase()
              .contains(_query.trim().toLowerCase()),
        )
        .toList();
    return AppDialog(
      scrollable: true,
      child: SizedBox(
        width: 480,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('record-search'),
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  labelText: t['record_search_label'],
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(t['no_data']))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final option = matches[index];
                        return ListTile(
                          title: Text(widget.labelOf(option)),
                          selected: option == widget.selected,
                          onTap: () => Navigator.pop(context, option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
