import { createHash, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { parseCfdi } from '../lib/cfdi-parser/index.js';
import { satStatus } from './sat.js';
import { StoreConflict, TENANT_ID_RE, relativePath, storeXml } from './store.js';

export const MAX_BODY_BYTES = Math.floor(7.5 * 1024 * 1024);
const MAX_CONCEPTOS_OUT = 20;
const BASE64_RE = /^[A-Za-z0-9+/]*={0,2}$/;
const UUID_RE = /^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$/i;
const RFC_RE = /^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$/;
const ROUTES = new Set(['/health', '/parse', '/sat-status', '/store']);

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}
const invalid = (code) => new HttpError(422, code);

const digest = (v) => createHash('sha256').update(v).digest();

function readBody(req) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length']);
    if (declared > MAX_BODY_BYTES) return reject(new HttpError(413, 'PAYLOAD_TOO_LARGE'));
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        chunks.length = 0;
        reject(new HttpError(413, 'PAYLOAD_TOO_LARGE'));
        req.pause();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', () => reject(new HttpError(400, 'BAD_REQUEST')));
  });
}

async function readJson(req) {
  const raw = await readBody(req);
  try {
    const body = JSON.parse(raw.toString('utf8'));
    if (body && typeof body === 'object' && !Array.isArray(body)) return body;
  } catch {
    // falls through
  }
  throw invalid('INVALID_BODY');
}

/** Decodes xmlBase64 into raw bytes, then runs the parser on them. Returns { bytes, data }. */
function parseXmlField(body) {
  const b64 = body.xmlBase64;
  if (typeof b64 !== 'string' || b64.length === 0 || b64.length % 4 !== 0 || !BASE64_RE.test(b64)) {
    throw invalid('INVALID_BODY');
  }
  const bytes = Buffer.from(b64, 'base64');
  // Magic bytes: optional UTF-8 BOM, then "<?xml" or "<cfdi:Comprobante". Rules out UTF-16, binaries, HTML.
  const head = bytes.subarray(bytes[0] === 0xef ? 3 : 0, (bytes[0] === 0xef ? 3 : 0) + 18).toString('latin1');
  if (!head.startsWith('<?xml') && !head.startsWith('<cfdi:Comprobante')) throw invalid('NOT_XML');
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    throw invalid('NOT_XML');
  }
  const res = parseCfdi(text);
  if (!res.ok) throw invalid(res.code);
  return { bytes, data: res.data };
}

/** Public shape consumed by the SQL procedure: exactly these keys, nothing from the raw XML. */
function toPublic(d, bytes) {
  const tax = (t) => ({
    impuesto: t.impuesto,
    tipoFactor: t.tipoFactor,
    tasaOCuota: t.tasaOCuota,
    baseCents: t.baseCents,
    importeCents: t.importeCents,
  });
  return {
    uuid: d.uuid,
    serie: d.serie,
    folio: d.folio,
    fechaEmision: d.fechaEmision,
    fechaTimbrado: d.fechaTimbrado,
    emisor: { rfc: d.emisor.rfc, nombre: d.emisor.nombre },
    receptor: { rfc: d.receptor.rfc, nombre: d.receptor.nombre },
    moneda: d.moneda,
    subtotalCents: d.subtotalCents,
    descuentoCents: d.descuentoCents,
    totalCents: d.totalCents,
    traslados: d.traslados.map(tax),
    retenciones: d.retenciones.map(tax),
    conceptos: d.conceptos.slice(0, MAX_CONCEPTOS_OUT).map((c) => ({
      claveProdServ: c.claveProdServ,
      descripcion: c.descripcion,
      importeCents: c.importeCents,
    })),
    // Hash of the raw bytes received, not of the re-encoded text the parser saw.
    sourceSha256: createHash('sha256').update(bytes).digest('hex'),
  };
}

export function createApp({ token, storageRoot, fetch: fetchImpl, satTimeoutMs, log = (line) => console.log(JSON.stringify(line)) }) {
  if (!token) throw new Error('CFDI_SERVICE_TOKEN is required');
  if (!storageRoot) throw new Error('STORAGE_ROOT is required');
  const tokenDigest = digest(token);

  const handlers = {
    '/health': async () => ({ status: 200, body: { ok: true } }),

    '/parse': async (req) => {
      const { bytes, data } = parseXmlField(await readJson(req));
      return { status: 200, body: toPublic(data, bytes) };
    },

    '/sat-status': async (req) => {
      const b = await readJson(req);
      if (
        typeof b.uuid !== 'string' || !UUID_RE.test(b.uuid) ||
        typeof b.emisorRfc !== 'string' || !RFC_RE.test(b.emisorRfc) ||
        typeof b.receptorRfc !== 'string' || !RFC_RE.test(b.receptorRfc) ||
        !Number.isSafeInteger(b.totalCents) || b.totalCents < 0 || b.totalCents >= 1e12
      ) {
        throw invalid('INVALID_BODY');
      }
      const status = await satStatus(
        { uuid: b.uuid.toUpperCase(), emisorRfc: b.emisorRfc, receptorRfc: b.receptorRfc, totalCents: b.totalCents },
        { fetch: fetchImpl, timeoutMs: satTimeoutMs },
      );
      return { status: 200, body: { status } };
    },

    '/store': async (req) => {
      const body = await readJson(req);
      if (typeof body.tenantId !== 'string' || !TENANT_ID_RE.test(body.tenantId)) throw invalid('INVALID_TENANT');
      if (typeof body.sha256 !== 'string') throw invalid('INVALID_BODY');
      const { bytes, data } = parseXmlField(body);
      const actual = createHash('sha256').update(bytes).digest('hex');
      if (body.sha256.toLowerCase() !== actual) throw invalid('SHA256_MISMATCH');
      const originalPath = relativePath(body.tenantId, data.fechaEmision, actual);
      try {
        await storeXml(storageRoot, originalPath, bytes);
      } catch (err) {
        if (err instanceof StoreConflict) throw new HttpError(409, 'CONFLICT');
        throw err;
      }
      return { status: 200, body: { originalPath } };
    },
  };

  const server = createServer(async (req, res) => {
    const started = process.hrtime.bigint();
    let bytesOut = 0;
    // Only the matched route name is logged, never the raw URL, headers or body.
    const route = ROUTES.has(req.url) ? req.url : 'unmatched';
    const send = (status, body) => {
      const payload = JSON.stringify(body);
      bytesOut = Buffer.byteLength(payload);
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': bytesOut, 'Cache-Control': 'no-store' });
      res.end(payload);
    };
    res.on('finish', () =>
      log({ method: req.method, route, status: res.statusCode, bytes: Number(req.headers['content-length']) || 0, ms: Number(process.hrtime.bigint() - started) / 1e6 }),
    );

    try {
      const handler = handlers[req.url];
      if (!handler) throw new HttpError(404, 'NOT_FOUND');
      const expected = req.url === '/health' ? 'GET' : 'POST';
      if (req.method !== expected) throw new HttpError(405, 'METHOD_NOT_ALLOWED');
      if (req.url !== '/health') {
        const given = req.headers['x-internal-token'];
        if (typeof given !== 'string' || !timingSafeEqual(digest(given), tokenDigest)) {
          throw new HttpError(401, 'UNAUTHORIZED');
        }
      }
      const out = await handler(req);
      send(out.status, out.body);
    } catch (err) {
      if (err instanceof HttpError) {
        const body = err.status === 422 || err.status === 413 ? { status: 'invalid', code: err.code } : { status: 'error', code: err.code };
        if (err.status === 413) res.setHeader('Connection', 'close');
        send(err.status, body);
      } else {
        send(500, { status: 'error', code: 'INTERNAL_ERROR' });
      }
    }
  });
  server.requestTimeout = 30_000;
  return server;
}
