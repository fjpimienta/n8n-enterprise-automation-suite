import { createHash } from 'node:crypto';
import { XMLParser, XMLValidator } from 'fast-xml-parser';

export const MAX_XML_BYTES = 2 * 1024 * 1024;
export const MAX_CONCEPTOS = 200;
// Fiscal decision: amounts must reconcile to the cent. Do not change silently (see README).
export const ROUNDING_TOLERANCE_CENTS = 0;

const CFDI_NS = 'http://www.sat.gob.mx/cfd/4';
const TFD_NS = 'http://www.sat.gob.mx/TimbreFiscalDigital';
const UUID_RE = /^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$/i;
const RFC_RE = /^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$/;
const AMOUNT_RE = /^(\d{1,13})(?:\.(\d{1,2}))?$/;
// Concept-level amounts may carry up to 6 decimals (SAT Anexo 20); the comprobante totals stay at 2.
const CONCEPT_AMOUNT_RE = /^(\d{1,13})(?:\.(\d{1,6}))?$/;
const DATETIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/;
const CONTROL_CHARS_RE = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/;
const CONTROL_CHARS_G = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g;
const CONCEPTO_TAG_RE = /<cfdi:Concepto[\s/>]/g;
const MAX_DESCRIPCION = 200;

const ARRAY_TAGS_RE =
  /(^|:)(Conceptos|Concepto|Traslado|Traslados|Retencion|Retenciones|Complemento|TimbreFiscalDigital|Emisor|Receptor|Impuestos)$/;

class CfdiError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const fail = (code, message) => {
  throw new CfdiError(code, message);
};

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  processEntities: false,
  htmlEntities: false,
  parseTagValue: false,
  parseAttributeValue: false,
  trimValues: true,
  ignoreDeclaration: true,
  ignorePiTags: true,
  isArray: (name) => ARRAY_TAGS_RE.test(name),
});

/** Strict string -> integer cents. Never goes through floating point arithmetic on decimals. */
function toCents(value, field) {
  const m = typeof value === 'string' ? AMOUNT_RE.exec(value) : null;
  if (!m) fail('INVALID_AMOUNT', `${field} is not a valid amount with at most 2 decimals`);
  return Number(m[1]) * 100 + Number((m[2] ?? '').padEnd(2, '0'));
}

/**
 * Concept-level amount -> integer cents, rounded half-up from the decimal string (no floating point).
 * Informational only: concept amounts are never used to reconcile the comprobante totals, which stay exact to the cent.
 */
function toCentsRounded(value, field) {
  const m = typeof value === 'string' ? CONCEPT_AMOUNT_RE.exec(value) : null;
  if (!m) fail('INVALID_AMOUNT', `${field} is not a valid amount with at most 6 decimals`);
  const frac = (m[2] ?? '').padEnd(3, '0');
  return Number(m[1]) * 100 + Number(frac.slice(0, 2)) + (frac.charCodeAt(2) >= 53 ? 1 : 0);
}

function decodeText(raw) {
  if (typeof raw !== 'string') return null;
  // Fixed predefined entities only; nothing is ever expanded from the document itself.
  const decoded = raw
    .replace(/&#x([0-9a-fA-F]{1,6});/g, (m, h) => safeCodePoint(parseInt(h, 16), m))
    .replace(/&#(\d{1,7});/g, (m, d) => safeCodePoint(parseInt(d, 10), m))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
  return decoded.replace(CONTROL_CHARS_G, '');
}

function safeCodePoint(cp, original) {
  return cp > 0 && cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff) ? String.fromCodePoint(cp) : original;
}

const attr = (node, name) => (node && typeof node === 'object' ? node[`@_${name}`] : undefined);
const kids = (node, key) => (node && typeof node === 'object' && Array.isArray(node[key]) ? node[key] : []);

function lineItems(container, tag, kind, requireImporte) {
  return kids(container, tag).map((node, i) => {
    const label = `${kind}[${i}]`;
    const tipoFactor = attr(node, 'TipoFactor');
    const exento = tipoFactor === 'Exento';
    if (kind === 'Traslado' ? !['Tasa', 'Cuota', 'Exento'].includes(tipoFactor) : tipoFactor !== 'Tasa') {
      fail('INVALID_STRUCTURE', `${label} has an unsupported TipoFactor`);
    }
    const impuesto = attr(node, 'Impuesto');
    if (typeof impuesto !== 'string' || !impuesto) fail('INVALID_STRUCTURE', `${label} has no Impuesto`);
    const importe = attr(node, 'Importe');
    if (exento && importe !== undefined) fail('INVALID_AMOUNT', `${label} is Exento and must not carry Importe`);
    if (!exento && requireImporte && importe === undefined) fail('INVALID_AMOUNT', `${label} has no Importe`);
    const tasa = attr(node, 'TasaOCuota');
    if (!exento && typeof tasa !== 'string') fail('INVALID_STRUCTURE', `${label} has no TasaOCuota`);
    return {
      impuesto,
      tipoFactor,
      tasaOCuota: exento ? null : tasa,
      baseCents: toCents(attr(node, 'Base'), `${label}.Base`),
      importeCents: exento ? null : toCents(importe, `${label}.Importe`),
    };
  });
}

const sum = (lines) => lines.reduce((acc, l) => acc + (l.importeCents ?? 0), 0);

function declaredNs(prefix, ...nodes) {
  for (const n of nodes) {
    const v = attr(n, prefix ? `xmlns:${prefix}` : 'xmlns');
    if (typeof v === 'string') return v;
  }
  return undefined;
}

function findStamps(root) {
  const stamps = [];
  for (const comp of kids(root, 'cfdi:Complemento')) {
    for (const key of Object.keys(comp)) {
      const m = /^(?:([^:]+):)?TimbreFiscalDigital$/.exec(key);
      if (!m || !Array.isArray(comp[key])) continue;
      for (const tfd of comp[key]) {
        const ns = declaredNs(m[1], tfd, comp, root);
        if (ns === undefined || ns === TFD_NS) stamps.push(tfd);
      }
    }
  }
  return stamps;
}

function preflight(xmlText) {
  if (typeof xmlText !== 'string') fail('NOT_XML', 'input is not a string');
  if (Buffer.byteLength(xmlText, 'utf8') > MAX_XML_BYTES) {
    fail('TOO_LARGE', `input exceeds ${MAX_XML_BYTES} bytes`);
  }
  const body = xmlText.charCodeAt(0) === 0xfeff ? xmlText.slice(1) : xmlText;
  if (!body.startsWith('<?xml') && !body.startsWith('<cfdi:Comprobante')) {
    fail('NOT_XML', 'input does not start with an XML declaration or cfdi:Comprobante');
  }
  if (/<!DOCTYPE|<!ENTITY/i.test(body)) fail('DOCTYPE_FORBIDDEN', 'DOCTYPE and ENTITY declarations are forbidden');
  if (CONTROL_CHARS_RE.test(body)) fail('INVALID_CHARS', 'input contains control characters');
  if ((body.match(CONCEPTO_TAG_RE) ?? []).length > MAX_CONCEPTOS) {
    fail('TOO_MANY_CONCEPTS', `input has more than ${MAX_CONCEPTOS} Concepto nodes`);
  }
  return body;
}

function extract(xmlText, body) {
  if (XMLValidator.validate(body) !== true) fail('NOT_XML', 'input is not well-formed XML');
  const root = parser.parse(body)['cfdi:Comprobante'];
  if (!root || typeof root !== 'object') fail('UNSUPPORTED_VERSION', 'root element is not cfdi:Comprobante');

  if (attr(root, 'Version') !== '4.0' || attr(root, 'xmlns:cfdi') !== CFDI_NS) {
    fail('UNSUPPORTED_VERSION', 'only CFDI 4.0 in the http://www.sat.gob.mx/cfd/4 namespace is supported');
  }
  if (attr(root, 'TipoDeComprobante') !== 'I') fail('UNSUPPORTED_TYPE', 'only TipoDeComprobante "I" is supported');
  if (attr(root, 'Moneda') !== 'MXN') fail('UNSUPPORTED_CURRENCY', 'only Moneda "MXN" is supported');

  const stamps = findStamps(root);
  const uuid = stamps.length === 1 ? attr(stamps[0], 'UUID') : undefined;
  if (typeof uuid !== 'string' || !UUID_RE.test(uuid)) {
    fail('NOT_STAMPED', 'exactly one TimbreFiscalDigital with a valid UUID is required');
  }
  const fechaTimbrado = attr(stamps[0], 'FechaTimbrado');
  const fecha = attr(root, 'Fecha');
  if (!DATETIME_RE.test(fecha ?? '') || !DATETIME_RE.test(fechaTimbrado ?? '')) {
    fail('INVALID_STRUCTURE', 'Fecha and FechaTimbrado must be yyyy-MM-ddTHH:mm:ss');
  }

  const parties = {};
  for (const [tag, label] of [['cfdi:Emisor', 'Emisor'], ['cfdi:Receptor', 'Receptor']]) {
    const list = kids(root, tag);
    if (list.length !== 1) fail('INVALID_STRUCTURE', `exactly one ${label} is required`);
    const rfc = String(attr(list[0], 'Rfc') ?? '').toUpperCase();
    if (!RFC_RE.test(rfc)) fail('INVALID_RFC', `${label} Rfc is not valid`);
    parties[label] = { rfc, nombre: decodeText(attr(list[0], 'Nombre')), node: list[0] };
  }

  const subtotalCents = toCents(attr(root, 'SubTotal'), 'SubTotal');
  const descuentoRaw = attr(root, 'Descuento');
  const descuentoCents = descuentoRaw === undefined ? 0 : toCents(descuentoRaw, 'Descuento');
  const totalCents = toCents(attr(root, 'Total'), 'Total');

  const impuestosList = kids(root, 'cfdi:Impuestos');
  if (impuestosList.length > 1) fail('INVALID_STRUCTURE', 'at most one comprobante-level Impuestos is allowed');
  const impuestos = impuestosList[0];
  const trasladosNodes = kids(impuestos, 'cfdi:Traslados');
  const retencionesNodes = kids(impuestos, 'cfdi:Retenciones');
  if (trasladosNodes.length > 1 || retencionesNodes.length > 1) {
    fail('INVALID_STRUCTURE', 'duplicate Traslados or Retenciones container');
  }
  const traslados = lineItems(trasladosNodes[0], 'cfdi:Traslado', 'Traslado', true);
  const retenciones = lineItems(retencionesNodes[0], 'cfdi:Retencion', 'Retencion', true);

  const sumTraslados = sum(traslados);
  const sumRetenciones = sum(retenciones);
  for (const [name, lines] of [['TotalImpuestosTrasladados', sumTraslados], ['TotalImpuestosRetenidos', sumRetenciones]]) {
    const declared = attr(impuestos, name);
    if (declared !== undefined && Math.abs(toCents(declared, name) - lines) > ROUNDING_TOLERANCE_CENTS) {
      fail('AMOUNTS_MISMATCH', `${name} (${toCents(declared, name)} cents) does not equal the sum of its lines (${lines} cents)`);
    }
  }

  const computed = subtotalCents - descuentoCents + sumTraslados - sumRetenciones;
  if (Math.abs(computed - totalCents) > ROUNDING_TOLERANCE_CENTS) {
    fail('AMOUNTS_MISMATCH', `computed ${computed} cents, declared Total ${totalCents} cents, difference ${totalCents - computed} cents`);
  }

  const conceptosNode = kids(root, 'cfdi:Conceptos')[0];
  const conceptoNodes = kids(conceptosNode ?? root, 'cfdi:Concepto');
  if (conceptoNodes.length === 0) fail('INVALID_STRUCTURE', 'at least one Concepto is required');
  const conceptos = conceptoNodes.map((node, i) => ({
    claveProdServ: decodeText(attr(node, 'ClaveProdServ')),
    descripcion: (decodeText(attr(node, 'Descripcion')) ?? '').slice(0, MAX_DESCRIPCION),
    importeCents: toCentsRounded(attr(node, 'Importe'), `Concepto[${i}].Importe`),
  }));

  return {
    uuid: uuid.toUpperCase(),
    serie: decodeText(attr(root, 'Serie')),
    folio: decodeText(attr(root, 'Folio')),
    fechaEmision: fecha,
    fechaTimbrado,
    emisor: { rfc: parties.Emisor.rfc, nombre: parties.Emisor.nombre },
    receptor: {
      rfc: parties.Receptor.rfc,
      nombre: parties.Receptor.nombre,
      usoCfdi: decodeText(attr(parties.Receptor.node, 'UsoCFDI')),
    },
    moneda: 'MXN',
    subtotalCents,
    descuentoCents,
    totalCents,
    traslados,
    retenciones,
    conceptos,
    sourceSha256: createHash('sha256').update(xmlText, 'utf8').digest('hex'),
  };
}

/**
 * Parses a CFDI 4.0 "Ingreso" invoice. Pure: no I/O, never throws.
 * Does NOT verify the SAT status of the UUID (see README).
 */
export function parseCfdi(xmlText) {
  try {
    return { ok: true, data: extract(xmlText, preflight(xmlText)) };
  } catch (err) {
    if (err instanceof CfdiError) return { ok: false, code: err.code, message: err.message };
    return { ok: false, code: 'NOT_XML', message: 'input could not be parsed' };
  }
}
