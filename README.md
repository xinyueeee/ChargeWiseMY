# ChargeWise MY — Infrastructure Planning

Flutter implementation of the EV Infrastructure Decision Support System planning module.

## Included

- MVVM structure under `lib/modules/planning`
- Dashboard, new proposal, proposal list, proposal details, gap analysis, and admin recommendation screens
- Local JSON fixtures in `assets/data`
- Google Maps markers for existing stations (green), proposed stations (blue), and priority areas (orange/red)
- One-reaction-only community support and immediate count update
- Rule-based recommendation: high demand, station distance above 5 km, and more than 30 supports produces `Suitable Location`

## Run

This workspace's Flutter wrapper could not generate native platform folders. On a normal Flutter workstation, run the following once from this folder (it preserves `lib/` and `assets/`):

```bash
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

Add a Google Maps API key before running on Android or iOS. Follow the official `google_maps_flutter` setup for the generated platform files.

## Backend hand-off

`PlanningRepository` is the integration boundary. Replace its local asset reads and empty mutation methods with API/Firebase calls; screens and view models remain unchanged.
