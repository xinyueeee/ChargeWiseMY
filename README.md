# ChargeWise MY

An EV charging infrastructure app for Malaysia, built with Flutter. It gives drivers a live map and cost tools for finding and using chargers, and gives administrators data-driven tools for planning where new infrastructure should go — combining official government open data with community-submitted proposals.

Built as a group project for **BMIT2073 Mobile Application Development**.

## Overview

ChargeWise MY has two portals behind a single sign-in:

- **Driver Portal** — find chargers, estimate charging cost, log sessions, report faults, and propose new charging locations for community review.
- **Admin Portal** — review and act on community proposals, run coverage-gap analysis to find underserved areas, manage user accounts, and triage fault reports.

The app is offline-resilient by design: national charging infrastructure data is synced from a live government API into a local SQLite cache, so core screens render instantly and keep working without a network connection.

## Features

### Driver Portal
| Feature | Description |
|---|---|
| **Home Dashboard** | National charging infrastructure overview with an interactive map, search, and charger-type filters |
| **Charging** | Charging cost calculator, session logging, and spending trend history |
| **Planning Dashboard** | Per-state infrastructure summary — existing chargers, MEVnet-proposed chargers, and community proposal activity |
| **Interactive Map** | Clustered charger markers with toggleable layers (Existing / MEVnet Proposed / Community Proposals) and priority-area overlays |
| **Gap Analysis** | Rule-based coverage-gap detection, ranked by priority, with an optional AI-generated plain-language interpretation |
| **Proposals** | Submit, browse, and react (support / not support) to community charging-location proposals, with site photos and map picking |
| **Feedback** | Report infrastructure faults and track resolution status |
| **Profile & Vehicles** | Account details, avatar, and multi-vehicle garage (Malaysia-focused make/model catalog) |

### Admin Portal
| Feature | Description |
|---|---|
| **Dashboard** | Cross-module overview of pending work: proposals, reports, and priority areas |
| **Proposal Management** | Review, approve/reject, and inspect community proposals against a rule-based suitability assessment |
| **AI Planning** | Gemini-backed review of proposals and coverage gaps — grounded strictly in the deterministic assessment, never allowed to override the score |
| **Feedback Management** | Triage and resolve driver-submitted fault reports |
| **User Management** | Search, filter, and activate/deactivate driver accounts, with a self-deactivation guard |
| **Admin Profile** | Account details and activity stats (proposals reviewed, reports resolved, etc.) |

## Architecture

- **Pattern:** MVVM — `ChangeNotifier` view models (via `provider`) separate screens from business logic.
- **Local cache:** SQLite (`sqflite`) holds a synced copy of national charging infrastructure for offline-first, stale-while-revalidate loading.
- **Backend:** Supabase (PostgreSQL + Auth + Storage + Edge Functions) for accounts, proposals, reactions, photos, and fault reports, protected by Row Level Security policies.
- **Server-side AI:** Gemini calls run inside Supabase Edge Functions, never on-device — API keys never reach the client, and the model is constrained by a system prompt to interpret supplied facts only, never to recalculate or override a deterministic score.

```
lib/
├── core/navigation/       # Driver/Admin shell scaffolding, bottom nav & rail
├── modules/
│   ├── auth/              # Login, register, role-based routing (AuthGate)
│   ├── home/               # Driver dashboard
│   ├── charging/            # Cost calculator, session logging
│   ├── planning/           # Dashboard, map, gap analysis, proposals (driver)
│   │   └── admin/          # Admin proposal review, AI planning assistant
│   ├── feedback/            # Fault reporting (driver + admin)
│   └── admin/               # Admin dashboard, user management, profile
└── services/                # Cross-cutting services (notifications, etc.)

supabase/
├── functions/               # Edge Functions (Gemini AI review, route ETA)
├── migrations/              # Schema migrations
└── sql/                     # Supporting SQL
```

## External Integrations

| Service | Used for | Where |
|---|---|---|
| [PLANMalaysia MEVnet](https://gisdev.planmalaysia.gov.my) | Official government EV charging infrastructure data (existing + proposed) | `lib/modules/planning/services/mevnet_api_service.dart` |
| [Supabase](https://supabase.com) | Auth, database, storage, Row Level Security, Edge Functions | throughout |
| [Google Maps Platform](https://developers.google.com/maps) | Map rendering, markers, clustering | `google_maps_flutter` |
| [Google Gemini](https://ai.google.dev) | Plain-language interpretation of deterministic Gap Analysis & proposal review results | `supabase/functions/gap-ai-analysis`, `supabase/functions/admin-proposal-ai-review` |
| [OpenRouteService](https://openrouteservice.org) | Real driving distance/duration for charging recommendations | `supabase/functions/charging-route-eta` |

## Tech Stack

- **Framework:** Flutter (Dart ≥ 3.3)
- **State management:** `provider`
- **Local storage:** `sqflite`, `shared_preferences`
- **Backend client:** `supabase_flutter`
- **Maps & location:** `google_maps_flutter`, `geolocator`
- **Other:** `image_picker`, `flutter_local_notifications`, `workmanager`, `url_launcher`

## Getting Started

### Prerequisites
- Flutter SDK (≥ 3.3.0)
- An Android or iOS device/emulator
- A Google Maps API key (Android/iOS)

### Setup

```bash
git clone https://github.com/xinyueeee/ChargeWiseMY.git
cd ChargeWiseMY
flutter pub get
flutter run
```

Supabase is pre-configured against the shared project in `lib/main.dart` (public anon key — safe to expose; access is governed by Row Level Security). No `.env` file is required to run the app.

### Backend (Edge Functions)

The three Supabase Edge Functions under `supabase/functions/` require these secrets to be set in the Supabase project (not committed to this repo):

| Secret | Used by |
|---|---|
| `GEMINI_API_KEY` | `gap-ai-analysis`, `admin-proposal-ai-review` |
| `ORS_API_KEY` | `charging-route-eta` |
| `SUPABASE_PUBLISHABLE_KEYS` | all three (server-side user auth check) |

## Testing

```bash
flutter analyze   # static analysis
flutter test       # 212 tests — unit, widget, and responsive-layout coverage
```

## Contributors

- [xinyueeee](https://github.com/xinyueeee) — Infrastructure Planning module (Dashboard, Interactive Map, Gap Analysis, Proposals, MEVnet integration)
- [yanhsii](https://github.com/yanhsii) — Charging & Home modules, authentication
- [khorzy-2414227](https://github.com/khorzy-2414227) — Admin module, feedback management
