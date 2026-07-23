export interface BreedCatalog {
  id?: string;
  especie: 'BOVINO' | 'BUFALO' | 'BORREGO';
  raza_grupo: string;
  raza_variante?: string;
  peso_adulto_hembra_kg: number;
  peso_adulto_macho_kg: number;
  pct_peso_primer_servicio: number;
  edad_min_pubertad_meses?: number;
  dias_gestacion_promedio: number;
  created_at?: string;
}
