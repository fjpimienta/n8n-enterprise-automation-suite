export declare const MAX_XML_BYTES: number;
export declare const MAX_CONCEPTOS: number;
export declare const ROUNDING_TOLERANCE_CENTS: number;

export type CfdiErrorCode =
  | 'TOO_LARGE'
  | 'NOT_XML'
  | 'DOCTYPE_FORBIDDEN'
  | 'INVALID_CHARS'
  | 'TOO_MANY_CONCEPTS'
  | 'UNSUPPORTED_VERSION'
  | 'UNSUPPORTED_TYPE'
  | 'UNSUPPORTED_CURRENCY'
  | 'NOT_STAMPED'
  | 'INVALID_RFC'
  | 'INVALID_AMOUNT'
  | 'AMOUNTS_MISMATCH'
  | 'INVALID_STRUCTURE';

export interface CfdiTax {
  impuesto: string;
  tipoFactor: 'Tasa' | 'Cuota' | 'Exento';
  /** Original string; null when Exento. */
  tasaOCuota: string | null;
  baseCents: number;
  /** null when Exento. */
  importeCents: number | null;
}

export interface CfdiData {
  uuid: string;
  serie: string | null;
  folio: string | null;
  fechaEmision: string;
  fechaTimbrado: string;
  emisor: { rfc: string; nombre: string | null };
  receptor: { rfc: string; nombre: string | null; usoCfdi: string | null };
  moneda: 'MXN';
  subtotalCents: number;
  descuentoCents: number;
  totalCents: number;
  traslados: CfdiTax[];
  retenciones: CfdiTax[];
  conceptos: { claveProdServ: string | null; descripcion: string; importeCents: number }[];
  sourceSha256: string;
}

export type ParseCfdiResult =
  | { ok: true; data: CfdiData }
  | { ok: false; code: CfdiErrorCode; message: string };

export declare function parseCfdi(xmlText: string): ParseCfdiResult;
