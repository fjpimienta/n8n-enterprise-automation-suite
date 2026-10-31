export const SAT_URL = 'https://consultaqr.facturaelectronica.sat.gob.mx/ConsultaCFDIService.svc';
export const SOAP_ACTION = 'http://tempuri.org/IConsultaCFDIService/Consulta';
export const SAT_TIMEOUT_MS = 10_000;

const ESTADOS = new Map([
  ['vigente', 'VIGENTE'],
  ['cancelado', 'CANCELADO'],
  ['no encontrado', 'NO_ENCONTRADO'],
]);

const xmlEscape = (s) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');

/** 0000000000.000000 (17 chars) from integer cents, with no floating point involved. */
export function formatTotal(totalCents) {
  const pesos = String(Math.floor(totalCents / 100)).padStart(10, '0');
  const cents = String(totalCents % 100).padStart(2, '0');
  return `${pesos}.${cents}0000`;
}

export function buildEnvelope({ uuid, emisorRfc, receptorRfc, totalCents }) {
  const expresion = `?re=${emisorRfc}&rr=${receptorRfc}&tt=${formatTotal(totalCents)}&id=${uuid}`;
  return (
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tem="http://tempuri.org/">' +
    '<soapenv:Header/><soapenv:Body><tem:Consulta>' +
    `<tem:expresionImpresa>${xmlEscape(expresion)}</tem:expresionImpresa>` +
    '</tem:Consulta></soapenv:Body></soapenv:Envelope>'
  );
}

/** Maps the Acuse.Estado element of the SOAP response; anything unexpected is ERROR. */
export function mapEstado(xml) {
  const m = /<(?:[\w.-]+:)?Estado(?:\s[^>]*)?>([^<]*)<\/(?:[\w.-]+:)?Estado>/.exec(xml);
  return (m && ESTADOS.get(m[1].trim().toLowerCase())) || 'ERROR';
}

async function attempt(fetchImpl, body, timeoutMs) {
  const res = await fetchImpl(SAT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'text/xml; charset=utf-8', SOAPAction: SOAP_ACTION },
    body,
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (res.status >= 500) throw new Error('upstream 5xx');
  if (!res.ok) return 'ERROR';
  return mapEstado(await res.text());
}

/** Never throws and never reports details: the caller only gets the mapped status. One retry. */
export async function satStatus(query, { fetch: fetchImpl = fetch, timeoutMs = SAT_TIMEOUT_MS } = {}) {
  const body = buildEnvelope(query);
  for (let i = 0; i < 2; i++) {
    try {
      return await attempt(fetchImpl, body, timeoutMs);
    } catch {
      // timeout, network failure or 5xx: retry once
    }
  }
  return 'ERROR';
}
