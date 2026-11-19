import { Campaign, CampaignError } from './palpation-campaigns';
import { CompareCategory, NeverPregnantRow } from './palpation-campaign-compare';
import type { ExportBlockReason } from './palpation-campaign-export';
import type { PairGroup } from './palpation-campaign-pairs';
import { FAMILY_COLOR, NO_RESULT_COLOR, UNINTERPRETED_COLOR } from './palpation-colors';
import { formatDate } from './palpation-view';

/** Spanish texts, labels and colours of the campaign views. Pure and display-only. */

export const COMPARE_NOTE = 'Compara resultados de palpación; no explica causas.';

export const CATEGORY_LABEL: Readonly<Record<CompareCategory, string>> = {
  'PREÑADA': 'Preñada',
  'VACÍA': 'Vacía',
  RANCHO: 'Definido por el rancho',
  SIN_INTERPRETAR: 'Sin interpretar',
  NO_PALPADA: 'Sin registro en esa campaña',
};

/** Short names of the categories, for the title of a cell list ("Sin registro en A y Preñada en B"). */
export const CATEGORY_SHORT: Readonly<Record<CompareCategory, string>> = {
  'PREÑADA': 'Preñada',
  'VACÍA': 'Vacía',
  RANCHO: 'Definido por el rancho',
  SIN_INTERPRETAR: 'Sin interpretar',
  NO_PALPADA: 'Sin registro',
};

/** The same family colours as the charts. A colour sample goes next to the name; the name and the number always say the same. */
export const CATEGORY_COLOR: Readonly<Record<CompareCategory, string>> = {
  'PREÑADA': FAMILY_COLOR.pregnant,
  'VACÍA': FAMILY_COLOR.empty,
  RANCHO: FAMILY_COLOR.ranch,
  SIN_INTERPRETAR: UNINTERPRETED_COLOR,
  NO_PALPADA: NO_RESULT_COLOR,
};

/** `01/09/2026 a 15/09/2026`. */
export function formatRange(c: Pick<Campaign, 'from' | 'to'>): string {
  return `${formatDate(c.from)} a ${formatDate(c.to)}`;
}

/** Spanish message of a validation error, for the editor. */
export function campaignErrorText(e: CampaignError): string {
  switch (e.code) {
    case 'too-few': return 'Define al menos 2 campañas para comparar.';
    case 'too-many': return 'Máximo 6 campañas.';
    case 'label-empty': return 'Escribe un nombre para la campaña.';
    case 'label-long': return 'El nombre es demasiado largo (máximo 40 caracteres).';
    case 'label-duplicate': return `Ya hay otra campaña llamada «${e.other ?? ''}».`;
    case 'from-invalid': return 'La fecha «Desde» no es válida.';
    case 'to-invalid': return 'La fecha «Hasta» no es válida.';
    case 'range-order': return '«Desde» no puede ser posterior a «Hasta».';
    case 'overlap': return `El rango se traslapa con «${e.other ?? ''}». Las campañas no pueden compartir días.`;
  }
}

/**
 * Wording of the "sin indicios de preñez" list. `appearsIn` counts the campaigns where the animal was palpated; `emptyIn` those where its latest
 * event is Vacía. A neutral description of results: it never names a cause.
 */
export function neverPregnantLabel(row: Pick<NeverPregnantRow, 'appearsIn' | 'emptyIn'>): string {
  if (row.appearsIn === 1) return 'Vacía en la única campaña';
  return row.emptyIn === 1 ? 'Vacía en 1 campaña' : `Vacía en ${row.emptyIn} campañas`;
}

/** Wording of the "sin interpretar" group: results that are not clinical, so they are never called vacía. */
export function uninterpretedLabel(row: Pick<NeverPregnantRow, 'appearsIn'>): string {
  return row.appearsIn === 1 ? 'Sin interpretar en la única campaña' : `Sin interpretar en ${row.appearsIn} campañas`;
}

/** Names of the two follow-up groups of a pair of campaigns, in the table titles and in the CSV. */
export const GROUP_LABEL: Readonly<Record<PairGroup, string>> = {
  PERSISTENT: 'Vacía en A y en B (persistente)',
  PENDING: 'Vacía en A y no palpada en B (seguimiento)',
  CELL: 'Celda de la matriz',
};

/** Why the export was refused, in Spanish. Nothing is written when it is refused. */
export function exportBlockText(reason: ExportBlockReason): string {
  switch (reason) {
    case 'no-tenant': return 'No hay una empresa activa válida: no se exporta nada.';
    case 'truncated': return 'El reporte está incompleto (se alcanzó el tope de filas): no se exporta para que una lista parcial no parezca completa.';
    case 'not-ready': return 'El reporte todavía no está listo: espera a que termine de cargar.';
    case 'invalid-campaigns': return 'Las campañas elegidas no son válidas: corrígelas antes de exportar.';
    case 'same-campaign': return 'Elige dos campañas distintas para exportar.';
    case 'foreign-company': return 'Hay datos de otra empresa en la respuesta: no se exporta nada.';
    case 'empty': return 'No hay animales en estos dos grupos: no hay nada que exportar.';
  }
}
