import 'package:flutter_test/flutter_test.dart';
import 'package:lightnetwork/widgets/searchable_picker.dart';

void main() {
  const items = ['CHALINZE', 'MBAGALA', 'BABUU', 'Mlandizi Adam'];

  test('empty query returns sorted items', () {
    final result = filterPickerItems(
      items: items,
      query: '',
      labelOf: (s) => s,
    );
    expect(result, ['BABUU', 'CHALINZE', 'MBAGALA', 'Mlandizi Adam']);
  });

  test('search matches location name case-insensitively', () {
    final result = filterPickerItems(
      items: items,
      query: 'mba',
      labelOf: (s) => s,
    );
    expect(result, ['MBAGALA']);
  });

  test('search also matches extra text such as agent name', () {
    final agents = [
      {'location': 'CHALINZE', 'name': 'Asha'},
      {'location': 'BABUU', 'name': 'Nassa Rocky'},
    ];
    final result = filterPickerItems(
      items: agents,
      query: 'nassa',
      labelOf: (a) => a['location']!,
      searchTextOf: (a) => '${a['name']} ${a['location']}',
    );
    expect(result.single['location'], 'BABUU');
  });

  test('no match returns empty list', () {
    final result = filterPickerItems(
      items: items,
      query: 'zzzz',
      labelOf: (s) => s,
    );
    expect(result, isEmpty);
  });
}
