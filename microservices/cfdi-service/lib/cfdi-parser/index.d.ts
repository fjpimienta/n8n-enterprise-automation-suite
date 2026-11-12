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
  | 'INVALID_STRUCTURE'
  | 'INVALID_PROFILE';

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

/** Extra keys of the 'sale' profile (palm sale register). Present only when the profile is requested. */
export interface CfdiSaleConcept {
  claveProdServ: string | null;
  /** Unit key as written in the voucher (e.g. 'KGM'); null when absent. */
  claveUnidad: string | null;
  /** Exact decimal string of the voucher, up to 6 decimals (never a float). */
  cantidad: string;
  /** Exact decimal string of the voucher, up to 6 decimals (never a float). */
  valorUnitario: string;
  descripcion: string;
  /** Concept amount in integer cents, rounded half up from the voucher's decimal string. */
  importeCents: number;
}

export interface CfdiSaleData extends Omit<CfdiData, 'conceptos'> {
  tipoComprobante: 'I';
  /** FormaPago / MetodoPago as written in the voucher; null when absent. */
  formaPago: string | null;
  metodoPago: string | null;
  conceptos: CfdiSaleConcept[];
}

export type ParseCfdiResult =
  | { ok: true; data: CfdiData }
  | { ok: false; code: CfdiErrorCode; message: string };

export type ParseCfdiSaleResult =
  | { ok: true; data: CfdiSaleData }
  | { ok: false; code: CfdiErrorCode; message: string };

export declare function parseCfdi(xmlText: string): ParseCfdiResult;
export declare function parseCfdi(xmlText: string, options: { profile: 'sale' }): ParseCfdiSaleResult;
