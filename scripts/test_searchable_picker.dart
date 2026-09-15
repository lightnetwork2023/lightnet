import '../lib/widgets/searchable_picker_logic.dart';

void main() {
  const items = ['CHALINZE', 'MBAGALA', 'BABUU', 'Mlandizi Adam'];

  var result = filterPickerItems(items: items, query: '', labelOf: (s) => s);
  assert(result.join(',') == 'BABUU,CHALINZE,MBAGALA,Mlandizi Adam', result.toString());

  result = filterPickerItems(items: items, query: 'mba', labelOf: (s) => s);
  assert(result.join(',') == 'MBAGALA', result.toString());

  final agents = [
    {'location': 'CHALINZE', 'name': 'Asha'},
    {'location': 'BABUU', 'name': 'Nassa Rocky'},
  ];
  final matched = filterPickerItems(
    items: agents,
    query: 'nassa',
    labelOf: (a) => a['location']!,
    searchTextOf: (a) => '${a['name']} ${a['location']}',
  );
  assert(matched.length == 1 && matched.single['location'] == 'BABUU');

  result = filterPickerItems(items: items, query: 'zzzz', labelOf: (s) => s);
  assert(result.isEmpty, result.toString());

  print('ok searchable picker filter');
}
