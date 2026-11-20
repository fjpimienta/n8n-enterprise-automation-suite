# Pending content after phase 3

All phase 2 tokens remain (see `../phase-2/TODO.md`). New in phase 3:

| Token | Where | Needs from the owner |
|---|---|---|
| `TODO_OG_IMAGE` | `core/seo.ts` (`og:image` and JSON-LD `image`) | A 1200x630 JPG or PNG (social crawlers do not all support WebP/AVIF) |
| `TODO_STREET_ADDRESS` | `core/seo.ts` (JSON-LD `streetAddress`) | Street address in Mérida for the LocalBusiness |
| `TODO_OPENING_HOURS` | `core/seo.ts` (JSON-LD `openingHours`) | Opening hours (schema.org format, e.g. `Mo-Fr 09:00-18:00`) |

A production build still fails while any of them (or a phase 2 token) is present: that is intended.
