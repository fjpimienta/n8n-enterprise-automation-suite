# Redesign D: report and marketing review list

Branch `feat/hosting3m-site-redesign-d`. Reference artboards: `docs/design/redesign-d/` (workspace `docs/`).

## Where things live
- **Tokens (one file):** `src/styles.css` (`@theme`: palette, fonts, radii, mock-screen colors; `@font-face`). A palette change is a one-file edit.
- **Copy (text-only edits):** `src/app/data/home-copy.ts` (hero, selector, services, steps, why, packages intro, contact), `systems-demo.ts`, `faq.ts`, `nav.ts`, `service-labels.ts`.
- **Business data (single source):** `src/app/core/business.ts` (legal entity, address, hours), read by the footer, contact section, terms page and JSON-LD.
- **Prices:** only from the catalog (`plans-snapshot.json` at build time, refreshed once after hydration). No template or data file carries a price.
- **Sections:** `src/app/sections/` (`hero`, `service-picker`, `services-bento`, `systems-demo`, `plans-section`, `steps-faq`, `contact-section`); layout in `src/app/layout/`.
- **Fonts:** `public/fonts/` (self-hosted, OFL). **Hero image:** `public/images/hero.webp` (PROVISIONAL, see below).

## Deviations from the artboards (and why)
1. **Logo and hero photo:** the artboards reference `/_blob/...` files that are not in the repo. The header uses a text wordmark and the hero a generated provisional WebP illustration (880x920). Replace `public/images/hero.webp` (same size) and add the real logo when available.
2. **Prices and specs:** the artboard prices and VPS specs are not hardcoded; they come from the catalog or are omitted. The "Desde ..." line in the selector is computed from the catalog.
3. **FAQ answers on IVA and billing period:** the artboard said prices never include IVA and that billing is annual in advance. The catalog can say otherwise per plan, so the answers defer to what each package shows.
4. **News and the open-source suite** are not in the 8-section list but are kept: news inside section 6 (light), the suite as a wide card in section 3 (dark), preserving the alternation.
5. **Mobile menu:** the 390 px artboard has none; a real hamburger was added (aria-expanded, Escape closes, focus returns).
6. **Demo requests** (`ERP hotelero (solicitud de demo)`, `Agro ERP (solicitud de demo)`) travel as the contact `service` value through `ContactPrefill`; they are not in the static list. Payload and endpoint are unchanged.
7. **`faq.json` became `faq.ts`** so entries can carry MARKETING-REVIEW comments.
8. **Bundle budget** warning raised from 350 kB to 360 kB (NgOptimizedImage for the LCP image adds about 2 kB).

## Measurements (local Lighthouse, mobile profile, Brotli, 3 runs)
Performance 90-93, best practices 96, SEO 100, accessibility 97 (the one contrast failure was fixed afterwards), FCP 0.9-1.0 s, **LCP 1.6-1.7 s (target < 1.2 s NOT met in this simulated slow-4G profile)**, CLS 0, TBT 310-400 ms. The LCP element is the hero image (preloaded, fetchpriority high). Measure again on beta behind Cloudflare. If still above target: `@defer` below-the-fold sections, reduce hydration work.

## Placeholder tokens: all resolved
`TODO_COPY` (four fallback card summaries), `TODO_PROFILE` (`/fjpimienta`), `TODO_PORTFOLIO` (`/portfolio`) and `TODO_OG_IMAGE` are resolved with approved content; no `TODO_` token remains and the production build passes. `scripts/check-todo.mjs` and its test are unchanged: a reintroduced token fails the production build again.

Profile photo: the original showed third-party brand signs, a bartender and part of a child. Only a tight, background-blurred crop (`public/images/profile-400.webp`) is committed; the original is not in the repo.

## MARKETING-REVIEW items
```
app.routes.ts:25:    // MARKETING-REVIEW: page description
app.routes.ts:32:    // MARKETING-REVIEW: page description
data/home-copy.ts:3: * Every string that depends on marketing validation carries a `// MARKETING-REVIEW` comment.
data/home-copy.ts:12:  eyebrow: 'Mérida, Yucatán · VPS · dominios · automatización', // MARKETING-REVIEW
data/home-copy.ts:13:  title: 'Soluciones en la nube para tu negocio', // MARKETING-REVIEW
data/home-copy.ts:14:  promise: 'Servidores, dominios y automatización con IA, instalados y administrados por una sola persona de confianza en Mérida.', // MARKETING-REVIEW
data/home-copy.ts:16:  ctaSecondary: 'Elige tu servicio', // MARKETING-REVIEW
data/home-copy.ts:21:    { title: 'Infraestructura de IONOS', text: 'Con atención personalizada' }, // MARKETING-REVIEW
data/home-copy.ts:22:    { title: 'Factura de Hosting3M', text: 'Un solo proveedor para todo' }, // MARKETING-REVIEW
data/home-copy.ts:24:    { title: 'Respuesta en 1 día hábil', text: 'Por WhatsApp o correo' }, // MARKETING-REVIEW
data/home-copy.ts:46:  title: '¿Qué necesitas hoy?', // MARKETING-REVIEW
data/home-copy.ts:47:  intro: 'Elige tu punto de partida y te muestro la mejor opción, con precio claro.', // MARKETING-REVIEW
data/home-copy.ts:54:      text: 'Servidor virtual para tu sistema o tu sitio. Autoadministrado, o administrado por Hosting3M.', // MARKETING-REVIEW
data/home-copy.ts:60:      text: 'Registro y administración de tu dominio, con las extensiones que necesites.', // MARKETING-REVIEW
data/home-copy.ts:66:      text: 'Flujos con n8n y modelos de lenguaje, instalados y operados por Hosting3M.', // MARKETING-REVIEW
data/home-copy.ts:72:      text: 'Sitios modernos, responsivos y optimizados para buscadores.', // MARKETING-REVIEW
data/home-copy.ts:89:  title: 'Todo en un solo lugar', // MARKETING-REVIEW
data/home-copy.ts:90:  intro: 'Instalo, configuro, administro y doy soporte. Tú te dedicas a tu negocio.', // MARKETING-REVIEW
data/home-copy.ts:109:  title: 'Así de simple', // MARKETING-REVIEW
data/home-copy.ts:115:  ], // MARKETING-REVIEW (the four steps)
data/home-copy.ts:119:  title: 'Por qué Hosting3M', // MARKETING-REVIEW
data/home-copy.ts:124:  ], // MARKETING-REVIEW (the three reasons)
data/home-copy.ts:132:  title: 'Paquetes con precio claro', // MARKETING-REVIEW
data/home-copy.ts:133:  intro: 'Precios en pesos mexicanos. Autoadministrado, o administrado por Hosting3M con instalación, configuración y soporte.', // MARKETING-REVIEW
data/home-copy.ts:140:  title: 'Cuéntame qué necesitas', // MARKETING-REVIEW
data/home-copy.ts:141:  intro: 'Escríbeme y te respondo en un día hábil, dentro del horario de atención. Sin compromiso.', // MARKETING-REVIEW
data/systems-demo.ts:13:  title: 'Míralo en acción', // MARKETING-REVIEW
data/systems-demo.ts:15:    'Dos sistemas desarrollados por Hosting3M y ya en operación: un ERP para hoteles, desde enero de 2026, y un ERP agropecuario con asistente de IA, desde noviembre 
data/systems-demo.ts:36:    lead: 'Habitaciones, reservas, huéspedes, personal, inventario y caja en un solo lugar, y desde el celular.', // MARKETING-REVIEW
data/systems-demo.ts:43:    ], // MARKETING-REVIEW (feature list)
data/systems-demo.ts:51:    lead: 'Controla tu hato y tus gastos, y pregúntale al asistente en lenguaje normal. En el chat web ya vienen asignadas tu empresa y tu UPP.', // MARKETING-REVIEW
data/systems-demo.ts:58:    ], // MARKETING-REVIEW (feature list)
data/systems-demo.ts:66:    lead: 'El sistema reconoce tu número de teléfono y lo liga a tu empresa y a tus UPP. Si tienes más de una, te pregunta a cuál se refiere antes de registrar.', // 
data/systems-demo.ts:71:    ], // MARKETING-REVIEW (feature list and security wording)
data/faq.ts:14:  // MARKETING-REVIEW: the three entries below come from the design artboard and are not approved copy yet.
data/profile.ts:10:    'Francisco Jesús Pérez Pimienta es ingeniero en Sistemas Computacionales y maestro en Administración de Proyectos, radicado en Mérida, Yucatán, con más de 20 años de e
data/profile.ts:19:  ], // MARKETING-REVIEW
data/portfolio.ts:17:  intro: 'Sistemas propios desarrollados por Hosting3M, ya en operación y en mejora continua.', // MARKETING-REVIEW
data/portfolio.ts:25:      text: 'Habitaciones, reservas, check-in y check-out, mantenimiento, inventario y caja, con un asistente de chat en evolución.', // MARKETING-REVIEW
data/portfolio.ts:32:      text: 'Capitalización y rendimiento del hato, censo por arete o RFID, palpaciones y cumplimiento normativo (UPP y licencias PSG), con asistente por chat web y por 
data/plans.json:2:  "_comment": "Static quote cards shown ONLY while the public catalog (POST /v6/plans) is empty. Prices, billing and features come from the API; never put them here. MARKET
data/nav.ts:1:/** Header navigation. Labels are copy (MARKETING-REVIEW); fragments must match the section ids on the home page. */
data/nav.ts:7:// MARKETING-REVIEW: menu labels and order
data/nav.ts:16:// MARKETING-REVIEW: header call to action
```

The four fallback card summaries in `src/app/data/plans.json` are approved copy; JSON cannot hold comments, see its `_comment`.
