import 'package:flutter/material.dart';
import 'searchable_picker_logic.dart';

export 'searchable_picker_logic.dart';

Future<T?> showSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
  String Function(T)? searchTextOf,
  T? selected,
  String searchHint = 'Search',
  Color? backgroundColor,
  Color? textColor,
  Color? hintColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return _SearchablePickerSheet<T>(
        title: title,
        items: items,
        labelOf: labelOf,
        subtitleOf: subtitleOf,
        searchTextOf: searchTextOf,
        selected: selected,
        searchHint: searchHint,
        textColor: textColor,
        hintColor: hintColor,
      );
    },
  );
}

class _SearchablePickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final String Function(T)? searchTextOf;
  final T? selected;
  final String searchHint;
  final Color? textColor;
  final Color? hintColor;

  const _SearchablePickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    this.subtitleOf,
    this.searchTextOf,
    this.selected,
    required this.searchHint,
    this.textColor,
    this.hintColor,
  });

  @override
  State<_SearchablePickerSheet<T>> createState() => _SearchablePickerSheetState<T>();
}

class _SearchablePickerSheetState<T> extends State<_SearchablePickerSheet<T>> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.textColor ?? Theme.of(context).colorScheme.onSurface;
    final hintColor = widget.hintColor ?? Theme.of(context).hintColor;
    final filtered = filterPickerItems(
      items: widget.items,
      query: _query.text,
      labelOf: widget.labelOf,
      searchTextOf: widget.searchTextOf,
    );
    final height = MediaQuery.of(context).size.height * 0.75;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: hintColor.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: textColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: hintColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                focusNode: _focus,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle: TextStyle(color: hintColor),
                  prefixIcon: Icon(Icons.search, color: hintColor),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.clear, color: hintColor),
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  filtered.isEmpty
                      ? 'No matches'
                      : '${filtered.length} of ${widget.items.length}',
                  style: TextStyle(color: hintColor, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.text.trim().isEmpty
                            ? 'No items'
                            : 'No results for "${_query.text.trim()}"',
                        style: TextStyle(color: hintColor),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final selected = item == widget.selected;
                        final subtitle = widget.subtitleOf?.call(item);
                        return ListTile(
                          title: Text(
                            widget.labelOf(item),
                            style: TextStyle(
                              color: textColor,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: subtitle == null || subtitle.isEmpty
                              ? null
                              : Text(subtitle, style: TextStyle(color: hintColor, fontSize: 12)),
                          trailing: selected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                          onTap: () => Navigator.pop(context, item),
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

class SearchablePickerField<T> extends StatelessWidget {
  final String label;
  final String hint;
  final String sheetTitle;
  final String searchHint;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final String Function(T)? searchTextOf;
  final ValueChanged<T> onChanged;
  final String? Function(T?)? validator;
  final IconData prefixIcon;
  final bool enabled;
  final InputDecoration? decoration;
  final Color? sheetBackgroundColor;
  final Color? sheetTextColor;
  final Color? sheetHintColor;
  final TextStyle? valueStyle;

  const SearchablePickerField({
    super.key,
    required this.label,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.value,
    this.hint = 'Search and select',
    this.sheetTitle = 'Select',
    this.searchHint = 'Type to search',
    this.subtitleOf,
    this.searchTextOf,
    this.validator,
    this.prefixIcon = Icons.location_on,
    this.enabled = true,
    this.decoration,
    this.sheetBackgroundColor,
    this.sheetTextColor,
    this.sheetHintColor,
    this.valueStyle,
  });

  Future<void> _open(BuildContext context) async {
    if (!enabled || items.isEmpty) return;
    final selected = await showSearchablePicker<T>(
      context: context,
      title: sheetTitle,
      items: items,
      labelOf: labelOf,
      subtitleOf: subtitleOf,
      searchTextOf: searchTextOf,
      selected: value,
      searchHint: searchHint,
      backgroundColor: sheetBackgroundColor,
      textColor: sheetTextColor,
      hintColor: sheetHintColor,
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: value,
      validator: validator,
      builder: (state) {
        if (value != state.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (state.mounted) state.didChange(value);
          });
        }
        final base = decoration ??
            InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: Icon(prefixIcon),
              suffixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            );
        return InkWell(
          onTap: enabled ? () => _open(context) : null,
          child: InputDecorator(
            decoration: base.copyWith(
              labelText: base.labelText ?? label,
              hintText: value == null ? (base.hintText ?? hint) : null,
              errorText: state.errorText,
              enabled: enabled,
              suffixIcon: base.suffixIcon ?? const Icon(Icons.search),
            ),
            isEmpty: value == null,
            child: Text(
              value == null ? '' : labelOf(value as T),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle ??
                  Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: enabled
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).disabledColor,
                      ),
            ),
          ),
        );
      },
    );
  }
}
