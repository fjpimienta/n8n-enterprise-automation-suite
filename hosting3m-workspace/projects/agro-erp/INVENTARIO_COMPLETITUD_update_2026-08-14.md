# Actualización — Inventario de completitud, corte 2026-08-14

Pegar como sección nueva al principio de `INVENTARIO_COMPLETITUD.md`, antes de "Resumen
ejecutivo", conservando el inventario original de 2026-07-29 íntegro debajo como historial.

---

## Actualización desde el corte anterior (2026-07-29 → 2026-08-14)

### Cerrado desde el corte anterior

- **Reglas de movimiento UPP↔PSG** (sección "Deuda técnica activa" del corte anterior):
  dejaron de estar en borrador. 16 filas confirmadas contra reglas de negocio reales del
  cliente; enforcement real sigue inactivo pendiente de un solo dato (ver abajo).
- **`herd_free_certificates` registrada en `crud_models`** — existía desde migración 024,
  nunca expuesta vía Meta-CRUD hasta ahora.
- Ver `ARCHITECTURE_DELTA_v1.10.0.md` y `DATABASE_SCHEMA_DELTA_v1.10.0.md` para el detalle
  técnico completo.

### Nuevo — Crítico, bloquea operación

#### `INTERNAL_SECRET` expuesto durante el trabajo de endurecimiento de `upload-file`

El valor real del secreto compartido entre `n8n-jwt-service` y `upload-file` se pegó en texto
plano en una sesión de trabajo (dos veces), incluyendo en el servidor de producción. Debe
tratarse como comprometido.

**Pendiente inmediato:** confirmar rotación de `INTERNAL_SECRET` (y considerar `JWT_SECRET`)
en ambos servicios, en ambos ambientes (espejo local y VPS de producción), con verificación
posterior (`curl` con el valor nuevo debe dar `200`; con el valor viejo debe dar `401`).

**Riesgo si no se resuelve:** cualquiera con el valor expuesto puede subir/leer archivos en
`upload-file` sin restricción, incluyendo futuras credenciales de identificación en
`compliance_documents`.

### Nuevo — Alto, requiere respuesta del cliente

#### Enforcement de `cattle_movement_rules` incompleto por una sola pregunta

14 de 16 filas tienen sus valores reales ya capturados pero `is_confirmed = false`. Falta
únicamente la respuesta del cliente sobre `requires_destination_ack`: ¿el flujo actual
(WhatsApp + folio REEMO, sin confirmación del destino en el sistema) es suficiente, o se
necesita un paso de acuse de recibo? Mensaje ya enviado a Alejandro/Pedro, sin respuesta al
corte de este documento.

**No bloquea el uso del sistema** — solo bloquea que el enforcement automático se active.

#### Nuevo titular: Juan Carlos (primo de Alejandro y Pedro)

Confirmado por el cliente: tenant propio (`id_company` independiente, sin sociedad con
Alejandro ni Pedro). Datos de sus UPP/PSG aún no entregados.

**Pendiente:** alta de tenant + UPP/PSG en cuanto lleguen los datos — mismo patrón ya
establecido para los otros dos titulares.

#### Confirmaciones pendientes sobre datos de Pedro (UPP 54)

Dos grupos distintos, ambos derivados del hallazgo de 21 registros `NOVILLO`/`VACÍA`
contradictorios documentado en el corte anterior:

- **Grupo 1 (corrección mecánica, 8 registros):** aretes con `category = NOVILLO` en el
  sistema pero `metadata.sexo_papel = "Novillona"` en el mismo registro — parece error de
  captura del campo `category`, no un conflicto real. Pendiente de que Pedro confirme antes
  de corregir (tocan datos reales de producción).
- **Grupo 2 (conflicto real, 2 registros, fuegos `1943` y `1811`):** el sistema dice vacías,
  la libreta de campo ya documentada dice preñadas. Pendiente de que Pedro indique cuál
  fuente es la correcta.

#### Lista final del archivo `TRATAMIENTO_LOTE_ROJO_VACIO_AGO_2026.xlsx`

Cruce de validación ya realizado (solo lectura, nada cargado): lote Blanco/Cebú con 37% de
coincidencia contra el sistema, lote Rojo/DM con 97%. Ambigüedad real detectada — varios
números de fuego corresponden a 3-4 animales distintos en el sistema, el fuego solo no
alcanza para identificar cuál recibió el tratamiento. Pendiente la lista final corregida del
cliente antes de cualquier carga real.

### Nuevo — Medio, sin bloquear nada hoy

#### Ambigüedad `requires_valid_psg` vs. `requires_health_tests` — documentada, no verificada independientemente

Se aclaró por escrito (migración 048) que son dos conceptos distintos (licencia del PSG vs.
estatus sanitario del animal), pero en la matriz confirmada de 042 ambas se fijaron con los
mismos valores bajo el supuesto de que coincidían. No se ha verificado contra un documento
real si de hecho coinciden siempre o si hay un caso donde divergen.

#### `jwt-service` — inconsistencia en `/verify-token`

El nodo n8n `Verify Token` manda un header `internal_secret`, pero el endpoint nunca lo
valida (solo `/generate-token` lo revisa). No es una regresión de seguridad — nada depende
hoy de que `/verify-token` lo exija — pero es una inconsistencia de diseño que vale la pena
cerrar.

#### `schema.sql` desactualizado (de nuevo)

Verificado 2026-08-14: cero coincidencias en el `schema.sql` versionado para cualquier
objeto de las migraciones 042-049. Regenerar con `pg_dump --schema-only` contra producción
antes de usarlo como fuente de diagnóstico — tercera vez que este archivo se desactualiza
respecto a producción (ver `CLAUDE.md`, regla 6, para las dos anteriores).

#### `cattle_movement_events` editable, no append-only

Decisión del cliente (no un descuido): la bitácora de movimientos permite `UPDATE` en vez de
un patrón de corrección append-only, pese a que un folio REEMO es un registro de
cumplimiento. Documentado como candidato a revisar si surge una necesidad real de corrección
posterior a la captura — no se ha revisitado desde entonces.

---

## [Inventario original — corte 2026-07-29 — conservado sin cambios debajo]
