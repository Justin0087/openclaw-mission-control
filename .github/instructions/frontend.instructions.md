---
applyTo: "frontend/**"
description: "Use when editing frontend TypeScript/React code: pages, components, API integration, styles, or E2E tests."
---
# Frontend Instructions

## Generated API Client
- `frontend/src/api/generated/` is **read-only**. Never edit files there; run `make api-gen` to regenerate.
- Orval splits output by OpenAPI tags into separate files with React Query hooks.
- The custom fetch layer in [src/api/mutator.ts](../../frontend/src/api/mutator.ts) handles auth token injection (local bearer or Clerk JWT) and `Content-Type` defaults.

## Pages & Components
- Pages use `"use client"` when interactive and follow the composition pattern: Shell template + organism components.
- Default export is named `Page` (e.g., `export default function Page() { ... }`).
- Components use `PascalCase` filenames; variables and functions use `camelCase`.

## Styling
- Tailwind CSS with `tailwindcss-animate` plugin. Config in [tailwind.config.cjs](../../frontend/tailwind.config.cjs).
- Dark mode is class-based (`darkMode: ["class"]`).
- Custom font families use CSS variables (`--font-heading`, `--font-body`, `--font-display`).

## Testing
- Unit tests: Vitest + Testing Library. Run with `make frontend-test`.
- E2E tests: Cypress in [frontend/cypress/e2e/](../../frontend/cypress/e2e/). Run with `cd frontend && npm run e2e`.
- Spec pattern: `cypress/e2e/**/*.cy.{js,jsx,ts,tsx}`.

## API URL Resolution
- `NEXT_PUBLIC_API_URL=auto` (default) resolves from the browser's current host to `:8000`.
- Set an explicit URL when behind a reverse proxy or non-default port.
