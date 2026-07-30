import 'proposal.dart';

const allStatesFilter = 'All States';

const malaysianStateOptions = <String>[
  allStatesFilter,
  'Johor',
  'Kedah',
  'Kelantan',
  'Kuala Lumpur',
  'Labuan',
  'Melaka',
  'Negeri Sembilan',
  'Pahang',
  'Penang',
  'Perak',
  'Perlis',
  'Putrajaya',
  'Sabah',
  'Sarawak',
  'Selangor',
  'Terengganu',
];

List<GapArea> filterPriorityAreasByState(
  Iterable<GapArea> areas,
  String selectedState,
) {
  if (selectedState == allStatesFilter) {
    return areas is List<GapArea> ? areas : List.unmodifiable(areas);
  }
  return List.unmodifiable(
    areas.where((area) => area.state == selectedState),
  );
}

int priorityAreaCountForState(
  Iterable<GapArea> areas,
  String state,
) =>
    state == allStatesFilter
        ? areas.length
        : areas.where((area) => area.state == state).length;
