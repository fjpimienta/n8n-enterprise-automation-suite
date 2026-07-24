export interface LifestageCatalog {
  id?: string;
  especie: 'BOVINO' | 'BUFALO' | 'BORREGO';
  categoria_origen: string;
  categoria_destino: string;
  edad_min_meses: number;
  requiere_validacion_peso: boolean;
  notas?: string;
  created_at?: string;
}
