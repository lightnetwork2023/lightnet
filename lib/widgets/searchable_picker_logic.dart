List<T> filterPickerItems<T>({
  required List<T> items,
  required String query,
  required String Function(T) labelOf,
  String Function(T)? searchTextOf,
}) {
  final q = query.trim().toLowerCase();
  final sorted = List<T>.from(items)
    ..sort((a, b) => labelOf(a).toLowerCase().compareTo(labelOf(b).toLowerCase()));
  if (q.isEmpty) return sorted;
  return sorted.where((item) {
    final label = labelOf(item).toLowerCase();
    final extra = (searchTextOf?.call(item) ?? '').toLowerCase();
    return label.contains(q) || extra.contains(q);
  }).toList();
}
