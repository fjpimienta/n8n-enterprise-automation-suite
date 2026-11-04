> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> **Las partes 1 y 2 ya están completadas y verificadas; la parte 3 sigue pendiente.** El panel debe mostrar
> «Sin guía» en la lista de autorizaciones mediante un PR posterior. `main` publica automáticamente los frontends
> por Plesk: no completar el release hasta cerrar esa parte pendiente.

# Runbook 096 — cumplimiento de venta según especie

## Propósito y regla

La migración 096 aplica los requisitos de arete oficial SINIIGA, situación TB/Brucelosis y guía de tránsito
únicamente a animales del régimen bovino: `species = 'BOVINO'` sin distinguir mayúsculas/minúsculas. Una especie
nula, vacía o desconocida también permanece estricta (fail-closed). Para cualquier otra especie (por ejemplo,
`BORREGO`, `BUFALO` o `EQUIDO`), estos tres requisitos no bloquean la venta. Antes de 096, solo `EQUIDO` estaba
exento del arete y TB/BR, y ninguna especie estaba exenta de la guía.

La migración agrega `fn_species_requires_bovine_compliance(species)` y reemplaza las funciones
`sp_solicitar_venta_orden`, `sp_procesar_venta_autorizada` y los overloads de 4 y 5 parámetros de
`sp_procesar_salida_ganado`. No modifica tablas, columnas, triggers, filas de `crud_models` ni datos.

## Orden de despliegue

1. Base de datos.
2. Workflows de n8n.
3. Frontend. La parte 3 de este release sigue pendiente: un PR posterior debe mostrar «Sin guía» en el panel de
   autorizaciones. No publicar el frontend antes de que las partes 1 y 2 estén verificadas.

## Parte 1 — base de datos

Ejecutar en producción con respaldo previo y conexión autorizada. Mantener el respaldo en `<RUTA_BACKUP>` y usar
`<CONEXION_PRODUCCION>` como placeholder de conexión:

1. Crear respaldo custom-format:

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   ```

2. Capturar el estado previo y confirmar `STATE OK: before`:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=before \
     -f 096_state_check.sql
   ```

   Conservar la salida de huellas para comparar. Las cuatro huellas `*_def` previas están documentadas en el
   encabezado de `096_state_check.sql`.

3. Ejecutar el dry run (sin `-v apply=true`); el script usa una transacción y revierte por defecto:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 \
     -f 096_species_scoped_sale_compliance.sql
   ```

4. Aplicar en una transacción:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true \
     -f 096_species_scoped_sale_compliance.sql
   ```

5. Verificar `STATE OK: applied` y comparar con la salida anterior. Las huellas de
   `cattle_livestock_data`, `pending_authorizations_data`, `historico_movimientos_count` y `crud_models` deben ser
   idénticas antes y después; las definiciones de funciones sí cambian.

6. Hacer la comprobación funcional solo en la empresa 3 y con animales de prueba: confirmar que una orden de
   borrego se aprueba, registra el ingreso y no requiere guía; confirmar también que un bovino sin arete oficial
   sigue rechazado y su autorización permanece pendiente. Revertir la transacción de prueba y verificar que no
   deje cambios persistentes.

### Protección contra drift

El guard de la migración aborta si alguna definición viva de las cuatro funciones difiere de la definición de
producción usada para preparar 096. Si aborta, detener el despliegue y comparar/reconstruir la migración desde la
definición viva. Nunca omitir el guard sin comparar y resolver primero el drift; no usar
`skip_drift_guard=true` como atajo.

El overload de 4 parámetros no se puede invocar directamente con cuatro argumentos porque sus parámetros con
default hacen ambigua la llamada frente al overload de 5 parámetros. Se verificó por definición (`pg_get_functiondef`)
y por su huella en `096_state_check.sql`, no mediante una llamada directa.

### Pruebas SQL

`096_tests.sql` es solo para LOCAL o una base de ensayo desechable; nunca ejecutarlo en producción. Usa registros
de prueba `T096-*` y termina con `ROLLBACK`. Requiere una cuenta ADMIN/EDITOR de la empresa de ensayo:

```sh
psql <CONEXION_LOCAL_O_ENSAYO> -v ON_ERROR_STOP=1 -v tenant=3 \
  -v admin=<CORREO_ADMIN_DE_PRUEBA> -f 096_tests.sql
```

Opcionalmente, `-v other=<ID_EMPRESA_DE_PRUEBA>` habilita el caso de aislamiento entre empresas. No reutilizar
animales ni cuentas reales.

## Parte 2 — workflows de n8n

Con la base de datos verificada, publicar los tres workflows incluidos en el cambio de agente: los prompts de
Chat y WhatsApp y `v6/MCP Server Cattle` con sus dos herramientas de venta. Descargar de nuevo cada workflow y
compararlo con `origin/develop`; confirmar que los tres exports sean idénticos antes de la prueba funcional.

Verificar en la empresa 3 con datos de prueba:

- Un bovino sin guía debe mostrar «Falta la guía de tránsito» en la vista previa.
- Un equino sin guía debe crear una orden de venta pendiente sin guía; un ADMIN la aprueba en el panel y la venta
  queda registrada sin guía.

## Parte 3 — frontend (pendiente)

Un PR posterior debe mostrar «Sin guía» en el panel de autorizaciones para estas órdenes. Los puntos indicados
para el cambio son `src/app/shared/utils/sale-order-grouping.util.ts` y
`src/app/features/admin/components/authorization-list/authorization-list.component.ts`.
`v6_Notificacion_Autorizaciones.json` ya renderiza «Sin guía»; no requiere ese ajuste.

## Rollback de base de datos

Si es necesario revertir 096, usar `096_rollback.sql` en una transacción. Primero ejecutar el dry run sin
`-v apply=true`; si la salida es correcta, aplicar:

```sh
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -f 096_rollback.sql
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true \
  -f 096_rollback.sql
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=rolled_back \
  -f 096_state_check.sql
```

La verificación debe reportar `STATE OK: rolled_back`; las cuatro huellas `sal4_def`, `sal5_def`, `venta_def` y
`orden_def` deben volver a los MD5 `before` listados en el encabezado de `096_state_check.sql`. Las huellas de
datos también deben seguir idénticas. La función auxiliar puede permanecer: ninguna de las funciones revertidas
la usa.

## Registro de despliegue

### Parte 1 — base de datos, 2026-11-03

- Se creó un respaldo `pg_dump -Fc` y se aplicó 096 en una sola transacción.
- `096_state_check.sql` reportó `applied`; las huellas de datos de ganado, autorizaciones pendientes,
  movimientos históricos y `crud_models` fueron idénticas antes y después.
- La prueba de aprobación end-to-end en la empresa 3 se revirtió: la orden de borrego se aprobó y registró el
  ingreso sin guía; el bovino sin arete oficial fue rechazado y permaneció pendiente.

### Parte 2 — n8n, 2026-11-04

- El PR #958, ya integrado en `develop`, actualizó los prompts de los nodos «AI Agent» de Chat y WhatsApp y las
  dos herramientas de venta del servidor MCP.
- Se publicaron los tres workflows en n8n y se verificó cada uno por descarga: idéntico a `origin/develop`.
- En la empresa 3, con datos de prueba, el bovino sin guía recibió «Falta la guía de tránsito» en la vista
  previa. El equino sin guía generó una orden pendiente sin guía; un ADMIN la aprobó en el panel y la venta se
  registró sin guía.

### Parte 3 — panel, pendiente

Queda pendiente el PR del panel para mostrar «Sin guía» en la lista de autorizaciones. La parte correspondiente
de n8n ya está cubierta por `v6_Notificacion_Autorizaciones.json`.
