# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AlchemIIIF is an Elixir/Phoenix 1.8 application for digitizing archaeological PDF reports into IIIF-compliant digital assets. It converts PDFs to images, supports polygon-based cropping, generates PTIFF tiles via libvips, and serves them through IIIF Image/Presentation APIs.

## Common Commands

```bash
mix setup              # Initial setup: deps + DB + assets
mix phx.server         # Start dev server (localhost:4000)
mix test               # Run all tests
mix test path/to/test.exs      # Run specific test file
mix test path/to/test.exs:42   # Run specific test by line
mix test --failed      # Re-run failed tests
mix format             # Auto-format code
mix review             # Full quality gate: compile(--warnings-as-errors) + credo(--strict) + sobelow + dialyzer
mix precommit          # Pre-push checks: compile + deps.unlock --unused + format + test
```

## Architecture

### Domain Modules (`lib/alchem_iiif/`)

- **Ingestion** — PDF→PNG conversion (poppler `pdftoppm` at 300 DPI) and image extraction
- **IIIF** — Manifest generation (JSON-LD) and PTIFF tile generation (via `vix`/libvips)
- **Pipeline** — Batch processing orchestrator with `ResourceMonitor` for CPU/memory-aware concurrency
- **Workers** — Per-user `GenServer` processes managed by `DynamicSupervisor` + `Registry`
- **Search** — PostgreSQL full-text search (tsvector + GIN indexes) with faceted filtering
- **Accounts** — User auth (`phx.gen.auth`), RBAC with `:admin`/`:user` roles, scoped via `current_scope`

### Web Layer (`lib/alchem_iiif_web/`)

- **LiveViews**: Lab (internal work), Inspector (5-step wizard), Gallery (public), Search, Admin
- **Controllers**: IIIF API endpoints, Download, Auth
- **JS Hooks** (`assets/js/hooks/`): `image_selection_hook.js` (polygon drawing), `openseadragon_hook.js` (zoom viewer)

### Key Patterns

- **Stage-Gate Workflow**: WIP → Pending Review → Approved/Returned (Lab→Gallery)
- **OTP Supervision**: DynamicSupervisor + Registry for user-scoped workers
- **PubSub**: Real-time progress updates via `AlchemIiif.PubSub`
- **Lazy PTIFF**: Public PTIF generated only on admin approval
- **Soft Delete**: Projects use `deleted_at` timestamp

## Tech Stack

- **Elixir 1.18+** / **OTP 27** / **Phoenix 1.8** / **LiveView 1.1**
- **PostgreSQL 15+** (JSONB, tsvector FTS)
- **libvips** (via `vix`) + **poppler-utils** (`pdftoppm`) for image processing
- **Tailwind CSS 4** + **DaisyUI 5** + **esbuild**
- **CropperJS**, **OpenSeadragon 4.1** (frontend)
- **Req** for HTTP (not httpoison/tesla)

## Code Conventions

- Comments and documentation in **Japanese**
- Conventional Commits: `feat(scope):`, `fix(scope):`, `docs:`, etc.
- `mix format` enforced; Credo strict mode (max line 120, nesting limit 4, cyclomatic complexity 12)
- `@current_scope` (not `@current_user`) — access user via `@current_scope.user`
- Fields set programmatically (e.g. `user_id`) must NOT be in `cast` calls
- Always use `to_form/2` for forms, `<.input>` component for inputs, `<.icon>` for icons
- LiveView streams for collections (not regular list assigns)
- No `Phoenix.View`, no `live_redirect`/`live_patch` (use `<.link navigate=…>`)
- Avoid LiveComponents unless strongly needed
- JS hooks go in `assets/js/`, never inline `<script>` tags in HEEx
- Accessibility: buttons min 60×60px, WCAG AA contrast, `aria-label` on interactive elements

## Branch Strategy

- `main` — stable, no direct push
- `develop` — integration branch
- `feature/*`, `fix/*`, `docs/*` — feature branches

## External Dependencies

- **libvips** and **poppler-utils** must be installed on the system (see Dockerfile for reference)
- Health check endpoint: `GET /api/health`
