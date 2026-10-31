# cfdi-parser

Standalone, pure parser for CFDI 4.0 "Ingreso" XML. No I/O, no network, no database.
Uses `fast-xml-parser` with entity processing disabled.

```js
import { parseCfdi } from './src/index.js';
const res = parseCfdi(xmlText); // { ok: true, data } | { ok: false, code, message }
```

`data`: `uuid` (uppercase), `serie`, `folio`, `fechaEmision`, `fechaTimbrado`, `emisor`, `receptor`,
`moneda`, `subtotalCents`, `descuentoCents`, `totalCents`, `traslados[]`, `retenciones[]`,
`conceptos[]`, `sourceSha256`. Types are in `src/index.d.ts`. Money is integer cents parsed from
strings (never floats); tax amounts are read as given, never computed. `Addenda`, `Certificado`
and every `Sello*` attribute are never copied to the output.

## Error codes
`TOO_LARGE` (> `MAX_XML_BYTES` = 2 MB), `NOT_XML`, `DOCTYPE_FORBIDDEN`, `INVALID_CHARS`,
`TOO_MANY_CONCEPTS` (> 200), `UNSUPPORTED_VERSION`, `UNSUPPORTED_TYPE` (only `I`),
`UNSUPPORTED_CURRENCY` (only `MXN`), `NOT_STAMPED`, `INVALID_RFC`, `INVALID_AMOUNT`,
`AMOUNTS_MISMATCH`, `INVALID_STRUCTURE` (missing or duplicated required nodes, bad dates or factors).

## Rounding tolerance
`ROUNDING_TOLERANCE_CENTS = 0`: `subtotal - descuento + traslados - retenciones` must equal `total`
to the cent, and `TotalImpuestos*` must equal the sum of their lines. This is a fiscal decision:
do not change it silently.

## Not done here
- The SAT status check (whether the UUID is valid or cancelled) is NOT performed.
- The stamp signature, certificate and seals are not verified.
- Concepto-level taxes and `sum(Concepto.Importe) = SubTotal` are not reconciled.
- The root and its children must use the `cfdi:` prefix.

## Tests
`npm install && npm test` (node:test, Node >= 20).
