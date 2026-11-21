# Pending content after phase 3

All phase 2 tokens remain (see `../phase-2/TODO.md`). New in phase 3 (`TODO_STREET_ADDRESS` and `TODO_OPENING_HOURS` were resolved afterwards):

| Token | Where | Needs from the owner |
|---|---|---|
| `TODO_OG_IMAGE` | `core/seo.ts` (`og:image` and JSON-LD `image`) | A 1200x630 JPG or PNG (social crawlers do not all support WebP/AVIF) |

A production build still fails while any of them (or a phase 2 token) is present: that is intended.
