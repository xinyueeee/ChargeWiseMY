# Module 3 – Infrastructure Feedback
## Implementation Plan: EV Driver Side

> Companion to `MODULES_IMPLEMENTATION_PLAN.md` (feature spec) and
> `MODULE3_ADMIN_IMPLEMENTATION_PLAN.md` (admin side, same feature).
> This document is the *how*, scoped to the driver-facing half of Module 3.

---

## 1. Scope recap

From `MODULES_IMPLEMENTATION_PLAN.md`:

* Submit Fault Report (photo + GPS auto capture)
* View Nearby Reported Issues
* View Report Status (Submitted → Verified → Resolved)
* CRUD 1 – Fault Report (Create / View / Update / Delete)

No AI, no admin actions. Everything here runs as the signed-in driver, scoped to
their own reports (plus read access to everyone's reports for "nearby issues").

---

## 2. Design consistency baseline

Reuse, don't reinvent. Everything below already exists and Module 3 should look
like it grew from the same app as Module 1/2:

| Concern | Existing source | Reuse plan |
|---|---|---|
| Colors (`green`, `blue`, text colors) | `planning_widgets.dart:11-14` | Import directly |
| Card shell | `AppCard` — `planning_widgets.dart:240` | Import directly |
| Stat tiles | `StatisticCard` — `planning_widgets.dart:267` | Import directly |
| Section headers | `PlanningSectionTitle` — `planning_widgets.dart:23` | Import directly |
| Loading / error / empty states | `PlanningLoadingState`/`PlanningErrorState`/`PlanningEmptyState` | Import directly |
| List-item card pattern | `ProposalCard` — `planning_widgets.dart:1786` | New `ReportCard`, same shape |
| Status pill | `StatusChip` — `planning_widgets.dart:1750` | New `ReportStatusChip`, same shape (3 states instead of 4) |
| Bottom nav | `FloatingBottomNav` — `planning_widgets.dart:1875` | **Activate the existing inert "Feedback" tab** |
| Form field labels | `AuthLabeledField` — `auth_widgets.dart:52` | Reuse styling convention (labeled field + red `*`) for the report form |
| Photo upload | `AuthService.uploadAvatar` — `auth_service.dart:102` | Same `image_picker` + Supabase Storage pattern |
| Map pin picker | `ProposalLocationMapScreen` — `proposal_location_map_screen.dart` | Reused as base for the report location screen |
| Address/state resolution | `ProposalLocationService` — `proposal_location_service.dart` | Reused as-is (it's already generic, not proposal-specific) |
| Screen chrome (AppBar) | white bg, `elevation: 0`, `foregroundColor: Colors.black`, `planningAppBarTitleStyle` | Match on every new screen |

**Cross-module import note:** the codebase already imports across module
boundaries (`planning_dashboard_screen.dart` imports `ProfileScreen` from the
`auth` module). Importing `planning_widgets.dart` from the new `feedback`
module is consistent with that precedent — no refactor needed to get started.
(A later cleanup could hoist the generic pieces — `AppCard`, colors, empty/error
states — into `lib/shared/`, but that's a cross-cutting change worth doing
together with whoever owns Module 1/2, not a Module 3 blocker.)

---

## 3. New dependency

`geolocator` is required for **GPS Auto Capture** — nothing in the repo does
device geolocation today (`proposal_location_map_screen.dart` only does
tap-to-pin, no `Geolocator` calls anywhere in `lib/`).

```yaml
# pubspec.yaml
dependencies:
  geolocator: ^13.0.0   # check latest at implementation time
```

Platform config needed:

* **Android** (`android/app/src/main/AndroidManifest.xml`): add
  `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` permissions.
* **iOS** (`ios/Runner/Info.plist`): add `NSLocationWhenInUseUsageDescription`.

---

## 4. Data model

### 4.1 Supabase table: `fault_reports`

Naming matches the existing `proposals` table conventions (`*_id` PK,
`user_id` FK, `status` free-text, `created_at`).

| Column | Type | Notes |
|---|---|---|
| `report_id` | `uuid` PK default `gen_random_uuid()` | |
| `user_id` | `uuid` FK → `users(id)` | reporter |
| `station_id` | `text` FK → `charging_stations(station_id)`, nullable | optional — a report may be about a station not in the catalog, or a general location |
| `category` | `text` | e.g. `Broken Connector`, `Not Charging`, `Damaged Screen`, `Payment Issue`, `Other` — dropdown, mirrors `charger_type` on `proposals` |
| `description` | `text` | |
| `photo_url` | `text`, nullable | public URL from Storage |
| `latitude` / `longitude` | `double precision` | from GPS auto-capture or manual pin adjust |
| `address` | `text` | resolved via `ProposalLocationService`, mirrors `proposals.address` |
| `status` | `text` default `'submitted'` | `submitted` / `verified` / `resolved` |
| `created_at` | `timestamptz` default `now()` | |
| `updated_at` | `timestamptz` default `now()` | |
| `verified_at`, `verified_by`, `resolved_at` | nullable | written by the admin side only |

Storage bucket: `fault_report_photos`, path `${userId}/${reportId}.${ext}` —
same shape as the existing `avatars` bucket path in `auth_service.dart:110`.

### 4.2 RLS (driver-relevant policies)

Draft only — review before applying in the Supabase SQL editor:

```sql
-- Anyone signed in can see all reports ("nearby reported issues" is community-wide,
-- same visibility model as `proposals`).
create policy "fault_reports_select_all_authenticated"
  on fault_reports for select
  to authenticated
  using (true);

create policy "fault_reports_insert_own"
  on fault_reports for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Drivers may only edit/delete their own report, and only before an admin
-- has started processing it.
create policy "fault_reports_update_own_while_submitted"
  on fault_reports for update
  to authenticated
  using (auth.uid() = user_id and status = 'submitted');

create policy "fault_reports_delete_own_while_submitted"
  on fault_reports for delete
  to authenticated
  using (auth.uid() = user_id and status = 'submitted');
```

(Admin-side policies — full select/update regardless of owner — are specified
in the admin plan, since they depend on the `users.role = 'admin'` check.)

### 4.3 Dart model — `lib/modules/feedback/models/fault_report.dart`

Same shape as `Proposal` in `planning/models/proposal.dart`: plain class,
`fromSupabase` factory, a `copyWith`-style helper for the location step.

```dart
class FaultReport {
  FaultReport({
    required this.id,
    required this.category,
    required this.description,
    required this.status,
    this.stationId,
    this.photoUrl,
    this.locationLabel = '',
    this.state,
    this.nearestTown,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.userId,
  });

  final String id, category, description;
  String status;
  final String? stationId;
  final String? photoUrl;
  final String locationLabel;
  final String? state;
  final String? nearestTown;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final String? userId;

  factory FaultReport.fromSupabase(Map<String, dynamic> row) => FaultReport(
        id: row['report_id'] as String,
        category: row['category'] as String? ?? 'Other',
        description: row['description'] as String? ?? '',
        status: row['status'] as String? ?? 'submitted',
        stationId: row['station_id'] as String?,
        photoUrl: row['photo_url'] as String?,
        locationLabel: (row['address'] as String?)?.trim() ?? '',
        latitude: CoordinateParser.latitude(row['latitude']),
        longitude: CoordinateParser.longitude(row['longitude']),
        createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
        userId: row['user_id'] as String?,
      );

  // Returns a copy with location fields overwritten (used once the picked
  // point resolves to a state / nearest town / display label).
  FaultReport copyWithLocation({
    required String locationLabel,
    required String state,
    required String nearestTown,
  }) =>
      FaultReport(
        id: id,
        category: category,
        description: description,
        status: status,
        stationId: stationId,
        photoUrl: photoUrl,
        locationLabel: locationLabel,
        state: state,
        nearestTown: nearestTown,
        latitude: latitude,
        longitude: longitude,
        createdAt: createdAt,
        userId: userId,
      );
}
```

Reuse `CoordinateParser` from `planning/models/proposal.dart` rather than
duplicating it — it's a generic lat/lng validator, not proposal-specific.

---

## 5. File structure

```
lib/modules/feedback/
  models/
    fault_report.dart
  services/
    location_capture_service.dart      # wraps Geolocator + ProposalLocationService
  viewmodels/
    feedback_viewmodel.dart            # ChangeNotifier, mirrors PlanningViewModel
  widgets/
    feedback_widgets.dart              # ReportCard, ReportStatusChip
  screens/
    report_list_screen.dart            # "My Reports" / "Nearby Issues" toggle
    report_details_screen.dart         # view + delete + edit entry
    new_report_screen.dart             # create + edit (dual-purpose, like NewProposalScreen)
    report_location_capture_screen.dart # GPS auto-capture + map pin adjust
    report_map_screen.dart             # simple map of nearby reports
```

Add fault-report + storage methods to the existing
`lib/services/supabase_service.dart` (same file `PlanningRepository` already
wraps for `proposals`), rather than creating a second Supabase client wrapper:

```dart
// Add to the SupabaseService class in supabase_service.dart
Future<List<Map<String, dynamic>>> getFaultReports() async {
  final response = await client
      .from('fault_reports')
      .select()
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(response);
}

Future<void> insertFaultReport(Map<String, dynamic> values) async {
  await client.from('fault_reports').insert(values);
}

Future<void> updateFaultReport(
  String reportId,
  Map<String, dynamic> values,
) async {
  await client.from('fault_reports').update(values).eq(
        'report_id',
        reportId,
      );
}

Future<void> deleteFaultReport(String reportId) async {
  await client.from('fault_reports').delete().eq(
        'report_id',
        reportId,
      );
}

Future<String> uploadFaultReportPhoto(String reportId, XFile file) async {
  final userId = client.auth.currentUser?.id ?? mockUserId;
  final bytes = await file.readAsBytes();
  final extension = file.name.contains('.')
      ? file.name.split('.').last.toLowerCase()
      : 'jpg';
  final path = '$userId/$reportId.$extension';
  await client.storage.from('fault_report_photos').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: file.mimeType),
      );
  return client.storage.from('fault_report_photos').getPublicUrl(path);
}
```

        
---

## 6. Screen-by-screen plan

### 6.1 `ReportListScreen`
Mirrors `proposal_list_screen.dart` almost exactly:
* AppBar: title "Fault Reports", white/flat, `+` action → `NewReportScreen`.
* Segmented toggle ("My Reports" / "Nearby Issues") sitting where the status
  dropdown does in `ProposalListScreen` — reuse `DropdownButtonFormField`
  styling or a `SegmentedButton` (Material 3 not enabled per `main.dart:32`
  `useMaterial3: false`, so prefer a `ToggleButtons`/chip-row for visual
  consistency with the rest of the app).
* Status filter dropdown (`All` / `Submitted` / `Verified` / `Resolved`) —
  same `DropdownMenuItem` pattern as `proposal_list_screen.dart:163-184`.
* Search field — same `TextField` + clear-icon pattern as
  `proposal_list_screen.dart:122-150`.
* List → `ReportCard` (new widget, shaped like `ProposalCard`).
* Empty state → `PlanningEmptyState` with a "Report an issue" CTA.
* `bottomNavigationBar: FloatingBottomNav(currentTab: 'Feedback', ...)`.

### 6.2 `NewReportScreen` (Create + Edit)
Mirrors `new_proposal_screen.dart`:
* `NewReportScreen({this.report})` — null = create, non-null = edit.
* Form fields: category dropdown, description (multiline, validated
  non-empty like `new_proposal_screen.dart:174-181`), photo picker (reuse
  `image_picker`, same crop/preview affordance as avatar upload), location
  card (delegates to `ReportLocationCaptureScreen`, same "Choose Location on
  Map" / "Change Location" card as `new_proposal_screen.dart:270-357`).
* On submit: upload photo first (if changed) → get URL → insert/update row →
  `Navigator.pop(context, true)` so the list screen reloads, exactly like
  `AddVehicleScreen` → `VehicleListScreen._addVehicle`.

### 6.3 `ReportLocationCaptureScreen`
New, but structurally a clone of `proposal_location_map_screen.dart`:
* On `initState`, immediately request the device location via
  `LocationCaptureService.getCurrentPosition()` (this *is* the "GPS Auto
  Capture" requirement) and drop a marker there.
* Same draggable-marker + "Use This Location" pattern as
  `proposal_location_map_screen.dart:104-227`, so a driver can nudge the pin
  if GPS is imprecise (e.g. indoor parking structure).
* Handle permission-denied / location-services-off gracefully: fall back to
  the existing tap-to-place flow with an inline `PlanningErrorState`-style
  banner ("Couldn't get your location — tap the map to place it manually").
* Resolve address/state/nearest-town via the existing
  `ProposalLocationService.resolve()` — no new geocoding logic needed.

### 6.4 `ReportDetailsScreen`
Mirrors `proposal_details_screen.dart`:
* Photo (if present), category, description, `ReportStatusChip`,
  read-only location preview (reuse `ProposalLocationMapScreen(readOnly:
  true, ...)` directly — it's already generic).
* "Edit" button → `NewReportScreen(report: report)` — only enabled while
  `status == 'submitted'` (matches the RLS policy in §4.2).
* "Delete" button → confirm dialog (same `AlertDialog` shape as
  `vehicle_list_screen.dart:41-60`) → delete → pop.
* Once `status != 'submitted'`, show a read-only banner explaining an admin
  is reviewing/has resolved it — no edit/delete affordance, so the UI matches
  what RLS will actually allow.

### 6.5 `ReportMapScreen` ("View Nearby Reported Issues")
* A focused map screen, not an extension of the heavyweight `MapPanel` in
  `planning_widgets.dart` (that widget is already a large, tuned piece of
  state for stations/proposals — bolting fault-report markers onto it is
  higher risk than it's worth). Instead, mirror the simpler
  `priority_area_map_screen.dart` / `proposal_location_map_screen.dart`
  pattern: a plain `GoogleMap` with report markers colored by status
  (submitted = orange, verified = blue, resolved = green — same semantics as
  `StatusChip`'s color mapping).
* Tapping a marker opens its info window with a "View details" affordance →
  `ReportDetailsScreen`.

---

## 7. State management

`FeedbackViewModel extends ChangeNotifier` (`lib/modules/feedback/viewmodels/feedback_viewmodel.dart`),
same shape as `PlanningViewModel`:

```dart
class FeedbackViewModel extends ChangeNotifier {
  FeedbackViewModel(this._repository);
  final FeedbackRepository _repository;

  List<FaultReport> myReports = const [];
  List<FaultReport> nearbyReports = const [];
  bool loading = true;
  String? errorMessage;

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final reports = await _repository.getReports();
      final userId = _repository.currentUserId;
      myReports = reports.where((r) => r.userId == userId).toList();
      nearbyReports = reports;
    } catch (error) {
      errorMessage = 'Unable to load fault reports. Please try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> submitReport(FaultReport draft, XFile? photo) async {
    await _repository.createReport(draft, photo);
    await load();
  }

  Future<void> updateReport(FaultReport report, XFile? newPhoto) async {
    await _repository.updateReport(report, newPhoto);
    await load();
  }

  Future<void> deleteReport(String id) async {
    await _repository.deleteReport(id);
    await load();
  }
}
```

Wire it in `main.dart` alongside the existing provider — switch the single
`ChangeNotifierProvider` to `MultiProvider`:

```dart
// main.dart — ChargeWiseApp
class ChargeWiseApp extends StatelessWidget {
  const ChargeWiseApp({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => PlanningViewModel(PlanningRepository())..load(),
          ),
          ChangeNotifierProvider(
            create: (_) => FeedbackViewModel(FeedbackRepository())..load(),
          ),
        ],
        child: MaterialApp(
          // ...existing MaterialApp config unchanged...
        ),
      );
}
```

---

## 8. Navigation wiring

`FloatingBottomNav` (`planning_widgets.dart:1875`) already renders a
"Feedback" tab but it's inert — no `onFeedbackTap` callback exists yet
(compare `onProfileTap`/`onPlanningTap`). Required edit:

```diff
 class FloatingBottomNav extends StatelessWidget {
   ...
   final VoidCallback? onProfileTap;
   final VoidCallback? onPlanningTap;
+  final VoidCallback? onFeedbackTap;
   ...
           Expanded(
-            child: _Nav(
-              Icons.warning_amber_outlined,
-              'Feedback',
-              selected: currentTab == 'Feedback',
+            child: GestureDetector(
+              onTap: onFeedbackTap,
+              child: _Nav(
+                Icons.warning_amber_outlined,
+                'Feedback',
+                selected: currentTab == 'Feedback',
+              ),
             ),
           ),
```

Then pass `onFeedbackTap: () => _push(context, const ReportListScreen())` from
every screen that currently instantiates `FloatingBottomNav`
(`planning_dashboard_screen.dart:362`, `proposal_list_screen.dart:282`,
`gap_analysis_screen.dart`, etc.) — small, additive, non-breaking change to a
shared widget.

---

## 9. Build sequence (suggested order)

1. Supabase: create `fault_reports` table + `fault_report_photos` bucket + RLS (§4).
2. Add `geolocator` dependency + platform permission entries (§3).
3. `FaultReport` model + `CoordinateParser` reuse (§4.3).
4. `supabase_service.dart` fault-report methods (§5).
5. `FeedbackRepository` + `FeedbackViewModel` (§7), wire into `main.dart`.
6. `FloatingBottomNav.onFeedbackTap` plumbing (§8) — do this early so every
   new screen is reachable as you build it.
7. `ReportListScreen` (empty-state only, no create flow yet) — get the tab
   navigable end-to-end first.
8. `ReportLocationCaptureScreen` (GPS capture is the riskiest new piece —
   validate permissions on a real device early).
9. `NewReportScreen` (create), then reuse for edit.
10. `ReportDetailsScreen` (view/delete).
11. `ReportMapScreen` ("nearby issues" map).
12. Polish: loading/error states, empty states, status-based edit/delete gating.

---

## 10. Open items to confirm with the team

* Whether `category` should be a fixed dropdown (recommended, matches
  `charger_type` UX) or free text — not specified in the feature list.
* Whether "nearby reported issues" should be distance-filtered (like
  proposals' `distance` field) or simply "all reports, sorted by recency" —
  spec doesn't say; distance filtering would reuse the same haversine helper
  already in `planning_repository.dart:255` (`_nearestStationKm`).
* Confirm with whoever builds the admin side (see
  `MODULE3_ADMIN_IMPLEMENTATION_PLAN.md`) that the RLS status-transition
  rules in §4.2 match their verify/resolve flow.