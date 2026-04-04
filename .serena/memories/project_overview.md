# AlchemIIIF Project Overview

## Purpose
Elixir/Phoenix app for digitizing archaeological PDF reports into IIIF-compliant digital assets. Converts PDFs to images, supports polygon-based cropping, generates PTIFF tiles via libvips, and serves through IIIF Image/Presentation APIs.

## Tech Stack
- Elixir 1.18+ / OTP 27 / Phoenix 1.8 / LiveView 1.1
- PostgreSQL 15+ (JSONB, tsvector FTS)
- libvips (via vix) + poppler-utils (pdftoppm)
- Tailwind CSS 4 + DaisyUI 5 + esbuild
- CropperJS, OpenSeadragon 4.1

## Structure
- `lib/alchem_iiif/` — Domain: Ingestion, IIIF, Pipeline, Workers, Search, Accounts
- `lib/alchem_iiif_web/` — Web: LiveViews (Lab, Inspector, Gallery, Admin), Controllers, JS Hooks
- `test/` — Tests with ConnCase, DataCase, Factory helpers
