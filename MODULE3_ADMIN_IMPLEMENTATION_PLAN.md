
# Module 3 – Infrastructure Feedback
## Implementation Plan: Administrator Side

> Companion to `MODULES_IMPLEMENTATION_PLAN.md` (feature spec) and
> `MODULE3_USER_IMPLEMENTATION_PLAN.md` (driver side, same feature — read that
> first for the `fault_reports` schema and `FaultReport` model, both shared).

---

## 1. Scope recap

From `MODULES_IMPLEMENTATION_PLAN.md`:

* View Submitted Fault Reports
* Verify Fault Reports
* Update Report Status
* Manage Maintenance Records
* CRUD 2 – Maintenance Record (Create / View / Update / Delete)

---

## 2. Access model: role-gated admin shell

**Current state of the app:** there is no admin/driver split at all today.
Module 2's admin actions (approve/reject a proposal) are just extra buttons
inside `AiPlanningScreen`, reachable by anyone — there's no role check
anywhere in the codebase (confirmed: `role` only appears in
`auth_service.dart:38` and `supabase_service.dart:78`, both just writing
`'driver'` on signup/mock-user creation; nothing reads it back).

Per your decision, Module 3's admin side gets a **real** role-gated
experience instead of repeating that pattern: after login, the app checks
`users.role` and routes to either the existing driver app or a new admin
shell. This is a small, additive change — no changes to `AuthGate` itself,
no new auth flow, and it reuses `AuthService.fetchProfile()`
(`auth_service.dart:52`) which already exists and already returns `role`.

### 2.1 New: `RoleRouter`

`lib/modules/auth/screens/role_router.dart` — sits between `AuthGate` and the
two "home" screens:

```dart
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});
  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  late final Future<Map<String, dynamic>?> _profile =
      AuthService().fetchProfile();

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: PlanningLoadingState(message: 'Loading your account…'),
            );
          }
          final role = snapshot.data?['role'] as String?;
          return role == 'admin'
              ? const AdminShell()
              : const PlanningDashboardScreen();
        },
      );
}
```

`main.dart:75-77` changes from:

```diff
- home: const AuthGate(authenticatedChild: PlanningDashboardScreen()),
+ home: const AuthGate(authenticatedChild: RoleRouter()),
```

That's the entire integration point — one line in `main.dart`, one new small
file. `AuthGate` stays exactly as it is (`auth_gate.dart` unchanged).

### 2.2 Provisioning an admin account

There's no admin sign-up UI, and there shouldn't be one — admins are
provisioned, not self-registered, same assumption the `role: 'driver'`
default in `register_screen.dart` already encodes. For development/demo,
promote an existing row manually in the Supabase table editor / SQL:

```sql
update users set role = 'admin' where email = 'your-test-admin@example.com';
```

### 2.3 RLS: admin policies

Admins need to see and mutate **every** row, not just their own. Draft
policies (review before applying):

```sql
-- Helper: is the current auth.uid() an admin?
create or replace function is_admin() returns boolean as $$
  select exists (
    select 1 from users where id = auth.uid() and role = 'admin'
  );
$$ language sql stable security definer;

create policy "fault_reports_admin_full_access"
  on fault_reports for all
  to authenticated
  using (is_admin())
  with check (is_admin());

create policy "maintenance_records_admin_full_access"
  on maintenance_records for all
  to authenticated
  using (is_admin())
  with check (is_admin());
```

(`security definer` so the policy check itself isn't blocked by RLS on
`users`.) These sit alongside, not instead of, the driver-owner policies
already drafted in the user-side plan §4.2.

---

## 3. Data model

### 3.1 `fault_reports`
Shared table — schema owned by the user-side plan (§4.1 there). Admin side
only adds writes to `status`, `verified_at`, `verified_by`, `resolved_at`.

### 3.2 New Supabase table: `maintenance_records`

| Column | Type | Notes |
| --- | --- | --- |
| `record_id` | `uuid` PK default `gen_random_uuid()` | |
| `report_id` | `uuid` FK → `fault_reports(report_id)`, nullable | set when the record closes out a specific fault report |
| `station_id` | `text` FK → `charging_stations(station_id)`, nullable | set for routine/preventive maintenance not tied to a report |
| `performed_by` | `uuid` FK → `users(id)` | the admin who logged it |
| `summary` | `text` | short title, e.g. "Replaced Type 2 connector" |
| `description` | `text` | |
| `maintenance_date` | `timestamptz` | when the work happened (may differ from `created_at`) |
| `cost` | `numeric`, nullable | optional |
| `created_at` / `updated_at` | `timestamptz` default `now()` | |

### 3.3 Dart models — `lib/modules/admin/models/`

`fault_report.dart` — **do not duplicate**; import
`FaultReport` from `lib/modules/feedback/models/fault_report.dart` (same
cross-module reuse precedent as `ProposalLocationService`). Only
`maintenance_record.dart` is new:

```dart
class MaintenanceRecord {
  MaintenanceRecord({
    required this.id,
    required this.summary,
    required this.description,
    required this.maintenanceDate,
    this.reportId,
    this.stationId,
    this.cost,
    this.performedBy,
    this.createdAt,
  });

  final String id, summary, description;
  final DateTime maintenanceDate;
  final String? reportId;
  final String? stationId;
  final double? cost;
  final String? performedBy;
  final DateTime? createdAt;

  factory MaintenanceRecord.fromSupabase(Map<String, dynamic> row) =>
      MaintenanceRecord(
        id: row['record_id'] as String,
        summary: row['summary'] as String? ?? '',
        description: row['description'] as String? ?? '',
        maintenanceDate:
            DateTime.tryParse('${row['maintenance_date'] ?? ''}') ??
                DateTime.now(),
        reportId: row['report_id'] as String?,
        stationId: row['station_id'] as String?,
        cost: (row['cost'] as num?)?.toDouble(),
        performedBy: row['performed_by'] as String?,
        createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
      );
}
```

---

## 4. File structure

```
lib/modules/admin/
  models/
    maintenance_record.dart
  services/
    admin_repository.dart          # wraps supabase_service.dart admin methods
  viewmodels/
    admin_viewmodel.dart           # ChangeNotifier, mirrors PlanningViewModel
  widgets/
    admin_widgets.dart             # AdminBottomNav, ReportQueueCard, MaintenanceRecordCard
  screens/
    admin_shell.dart               # bottom-nav scaffold: Dashboard / Reports / Maintenance
    admin_dashboard_screen.dart
    admin_report_list_screen.dart
    admin_report_details_screen.dart
    maintenance_list_screen.dart
    new_maintenance_record_screen.dart

lib/modules/auth/screens/
    role_router.dart               # new — see §2.1
```

`supabase_service.dart` additions (alongside the fault-report methods added
for the driver side):

```dart
// Add to the SupabaseService class in supabase_service.dart
Future<List<Map<String, dynamic>>> getAllFaultReports() async {
  final response = await client
      .from('fault_reports')
      .select()
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(response);
}

Future<void> updateFaultReportStatus(
  String reportId,
  String status, {
  String? adminId,
}) async {
  await client.from('fault_reports').update({
    'status': status,
    if (status == 'verified') 'verified_at': DateTime.now().toIso8601String(),
    if (status == 'verified') 'verified_by': adminId,
    if (status == 'resolved') 'resolved_at': DateTime.now().toIso8601String(),
  }).eq('report_id', reportId);
}

Future<List<Map<String, dynamic>>> getMaintenanceRecords() async {
  final response = await client
      .from('maintenance_records')
      .select()
      .order('maintenance_date', ascending: false);
  return List<Map<String, dynamic>>.from(response);
}

Future<void> insertMaintenanceRecord(Map<String, dynamic> values) async {
  await client.from('maintenance_records').insert(values);
}

Future<void> updateMaintenanceRecord(
  String recordId,
  Map<String, dynamic> values,
) async {
  await client.from('maintenance_records').update(values).eq(
        'record_id',
        recordId,
      );
}

Future<void> deleteMaintenanceRecord(String recordId) async {
  await client.from('maintenance_records').delete().eq(
        'record_id',
        recordId,
      );
}
```

---

## 5. Design consistency

Same visual language as the driver app — an admin panel that looks like a
different product is the thing to avoid. Reuse table from the user-side plan
§2 applies here too (`AppCard`, `StatisticCard`, `PlanningSectionTitle`,
loading/error/empty states, AppBar chrome). Two admin-specific additions:

* **`AdminBottomNav`** (new, in `admin_widgets.dart`) — same rounded pill
  shell as `FloatingBottomNav` (`planning_widgets.dart:1891-1949`: white
  container, `borderRadius: 20`, same border/shadow), but with admin-relevant
  tabs instead of driver ones: `Dashboard` / `Reports` / `Maintenance` /
  `Profile`. Don't reuse `FloatingBottomNav` itself — its tab set
  (Home/Charging/Planning/Feedback/Profile) is driver-specific and its
  `currentTab` strings are hardcoded to that set.
* **`ReportStatusChip`** — import from the `feedback` module
  (`lib/modules/feedback/widgets/feedback_widgets.dart`) rather than
  reimplementing; the admin screens need the exact same three-state
  color mapping the driver sees, or "Verified" won't mean the same color in
  both places.

`ProfileScreen` (`auth/screens/profile_screen.dart`) is reused as-is for the
admin's own profile tab — no admin-specific fork needed there.

---

## 6. Screen-by-screen plan

### 6.1 `AdminShell`
Thin `Scaffold` + `IndexedStack` (or `Navigator` per tab, matching how the
driver side just pushes routes rather than nesting navigators — keep it
simple and consistent: a single `Scaffold` whose `body` swaps based on the
selected tab, `bottomNavigationBar: AdminBottomNav`). This becomes the
`RoleRouter`'s admin destination.

### 6.2 `AdminDashboardScreen`
Mirrors `planning_dashboard_screen.dart`'s stat-grid section
(`planning_dashboard_screen.dart:256-299`) almost exactly:

```dart
Widget _statsGrid(int columns) => GridView.count(
      crossAxisCount: columns,
      children: [
        StatisticCard(value: '$pendingCount', label: 'Pending Verification', icon: Icons.report_outlined, color: Colors.orange),
        StatisticCard(value: '$verifiedCount', label: 'Verified', icon: Icons.fact_check_outlined, color: blue),
        StatisticCard(value: '$resolvedCount', label: 'Resolved', icon: Icons.check_circle_outline, color: green),
        StatisticCard(value: '$openMaintenanceCount', label: 'Open Maintenance', icon: Icons.build_outlined, color: Colors.deepPurple),
      ],
    );
```

Quick actions row below (same `ElevatedButton.icon`/`OutlinedButton.icon`
pair pattern as `planning_dashboard_screen.dart:306-356`): "Review Reports"
→ `AdminReportListScreen`, "Log Maintenance" → `NewMaintenanceRecordScreen`.

### 6.3 `AdminReportListScreen`
Mirrors `proposal_list_screen.dart` (search field, status dropdown, result
count, `ListView.builder`) but sourced from **all** reports
(`AdminRepository.getAllReports()`), not just the signed-in user's. List item
is `ReportQueueCard` — like `ReportCard` from the driver side but with the
reporter's name/avatar surfaced (admins need to know who filed it; drivers
don't need to see that on their own list).

### 6.4 `AdminReportDetailsScreen`
Mirrors `ai_planning_screen.dart`'s status-action pattern
(`_pendingStatus`/`_updatingStatus` local state while a status write is in
flight, disabling the button during the call):

* Full report: photo, category, description, reporter, submitted date,
  read-only map preview (reuse `ProposalLocationMapScreen(readOnly: true)`).
* Status actions, gated by current status (same idea as
  `ai_planning_screen.dart`'s approved/rejected branching):
  * `submitted` → **Verify** button (`status: 'verified'`, stamps
    `verified_at`/`verified_by`).
  * `verified` → **Mark Resolved** button (`status: 'resolved'`, stamps
    `resolved_at`) *and* **Log Maintenance Record** button, prefilling
    `NewMaintenanceRecordScreen(reportId: report.id, stationId: report.stationId)`.
  * `resolved` → read-only, shows linked maintenance record(s) if any.
* Every status write goes through `AdminViewModel.updateReportStatus(...)`
  → `AdminRepository.updateStatus(...)` → `supabase_service.dart`'s
  `updateFaultReportStatus`, same call shape as
  `planning_viewmodel.dart:540` → `planning_repository.dart:252` →
  `supabase_service.dart:91` (`updateProposalStatus`) for Module 2.

### 6.5 `MaintenanceListScreen`
Mirrors `vehicle_list_screen.dart`'s simple list+FAB CRUD shape (`FutureBuilder`
+ `ListView.separated` + delete-confirm `AlertDialog` + bottom
`ElevatedButton.icon` "Add" button) — that screen is the closest existing
analog to a flat CRUD list without a companion detail screen, which fits
maintenance records well (edit inline via the same form, no separate details
view needed).

### 6.6 `NewMaintenanceRecordScreen` (Create + Edit)
Mirrors `new_proposal_screen.dart`'s dual-purpose create/edit shape:
* `NewMaintenanceRecordScreen({this.record, this.reportId, this.stationId})`.
* Fields: summary, description, maintenance date (`showDatePicker`, styled
  to match the app's `OutlineInputBorder` inputs), cost (numeric,
  optional), linked report/station shown read-only if pre-filled from
  `AdminReportDetailsScreen`, otherwise a picker.
* Submit → insert/update → pop with `true` → list reloads, same as
  `AddVehicleScreen`.

---

## 7. State management

`AdminViewModel extends ChangeNotifier` (`lib/modules/admin/viewmodels/admin_viewmodel.dart`):

```dart
class AdminViewModel extends ChangeNotifier {
  AdminViewModel(this._repository);
  final AdminRepository _repository;

  List<FaultReport> reports = const [];
  List<MaintenanceRecord> maintenanceRecords = const [];
  bool loading = true;
  String? errorMessage;

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      reports = await _repository.getAllReports();
      maintenanceRecords = await _repository.getMaintenanceRecords();
    } catch (error) {
      errorMessage = 'Unable to load admin data. Please try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> verifyReport(FaultReport report) =>
      updateReportStatus(report, 'verified');

  Future<void> resolveReport(FaultReport report) =>
      updateReportStatus(report, 'resolved');

  Future<void> updateReportStatus(FaultReport report, String status) async {
    await _repository.updateStatus(report.id, status);
    await load();
  }

  Future<void> submitMaintenanceRecord(MaintenanceRecord draft) async {
    await _repository.saveMaintenanceRecord(draft);
    await load();
  }

  Future<void> deleteMaintenanceRecord(String id) async {
    await _repository.deleteMaintenanceRecord(id);
    await load();
  }

  int get pendingCount => reports.where((r) => r.status == 'submitted').length;
  int get verifiedCount => reports.where((r) => r.status == 'verified').length;
  int get resolvedCount => reports.where((r) => r.status == 'resolved').length;
}
```

Provider wiring: **only** create this provider inside `AdminShell`'s subtree
(e.g. wrap `AdminShell`'s child in `ChangeNotifierProvider`), not globally in
`main.dart` — a driver's session should never construct an `AdminViewModel`
or issue admin-scoped queries that RLS will reject anyway. This also means
`RoleRouter` naturally keeps admin state out of memory for driver sessions.

---

## 8. Build sequence (suggested order)

1. Confirm the driver-side `fault_reports` table + RLS exist first (this plan
   depends on it) — see `MODULE3_USER_IMPLEMENTATION_PLAN.md` §4.
2. Supabase: create `maintenance_records` table + `is_admin()` helper +
   admin RLS policies (§2.3, §3.2).
3. Provision a test admin account (§2.2).
4. `RoleRouter` + one-line `main.dart` change (§2.1) — verify a driver
   account still lands on `PlanningDashboardScreen` unchanged, and the admin
   account lands on a placeholder `AdminShell` scaffold.
5. `MaintenanceRecord` model, `AdminRepository`, `AdminViewModel` (§3.3, §7).
6. `AdminShell` + `AdminBottomNav` (§5, §6.1) — get all four tabs navigable
   with placeholder bodies.
7. `AdminDashboardScreen` (§6.2).
8. `AdminReportListScreen` → `AdminReportDetailsScreen` with Verify/Resolve
   actions (§6.3, §6.4) — this is the core of the module.
9. `MaintenanceListScreen` + `NewMaintenanceRecordScreen` (§6.5, §6.6).
10. Cross-check: verifying/resolving a report from the admin side should be
    reflected next time the driver reopens `ReportDetailsScreen` — test the
    full loop between both sides.

---

## 9. Open items to confirm with the team

* Whether `maintenance_records` should be driver-visible read-only (spec
  doesn't ask for it, but "transparency" is a reasonable product argument) —
  currently scoped admin-only per the literal feature list.
* Whether a report needs to pass through `verified` before it can be
  `resolved`, or whether an admin can jump straight to `resolved` — this plan
  assumes the strict Submitted → Verified → Resolved order from the spec's
  "Report Status" list; relax the RLS/UI gating in §6.4 if the team wants a
  shortcut.
* Confirm the `is_admin()` RLS helper naming/pattern doesn't collide with
  anything Module 1/2 owners are planning for their own admin work later —
  worth a quick sync since `role` is a shared column.