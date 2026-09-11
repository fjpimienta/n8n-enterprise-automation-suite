export type TipoEventoAutorizacion = 'BAJA_MORTANDAD' | 'VENTA';
export type EstadoAutorizacion = 'PENDIENTE' | 'APROBADO' | 'RECHAZADO' | 'EXPIRADO';

/** Shape embebido vía el join declarativo del modelo Meta-CRUD (alias `cattle_livestock_data`). */
export interface PendingAuthorizationLivestock {
  id: string;
  electronic_rfid?: string | null;
  rfid_siniiga?: string | null;
  numero_fuego?: string | null;
  category?: string;
  species?: string;
}

/** Payload JSONB — shape observado en producción (sp_solicitar_autorizacion). No es fijo por
 *  tipo_evento fuera de los campos comunes de identificación. */
export interface PendingAuthorizationPayload {
  electronic_rfid?: string | null;
  rfid_siniiga?: string | null;
  numero_fuego?: string | null;
  causa_mortandad?: string;
  descripcion?: string;
  fecha_evento?: string;
  [key: string]: unknown;
}

export interface PendingAuthorization {
  id: string;
  id_company: number;
  livestock_id: string;
  tipo_evento: TipoEventoAutorizacion;
  payload: PendingAuthorizationPayload;
  solicitado_por_email: string;
  fecha_solicitud: string;
  estado: EstadoAutorizacion;
  resuelto_por_email?: string | null;
  fecha_resolucion?: string | null;
  notas_resolucion?: string | null;
  cattle_livestock_data?: PendingAuthorizationLivestock | null;
}
