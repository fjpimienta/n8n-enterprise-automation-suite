> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n verificados con sus huellas).
> `main` publica automáticamente los frontends por Plesk. El orden obligatorio es base de datos → workflows →
> frontend. No publiques el frontend antes de completar y verificar las partes 1 y 2.

# Runbook 097 — selección FIFO para ventas de animales no identificados

## Alcance

La migración agrega `seleccion: "FIFO"` a los items de lote de `sp_solicitar_venta_orden`. Requiere lote,
categoría y cantidad positiva; selecciona en la base de datos exactamente esa cantidad de animales no bovinos sin
identificadores y sin solicitudes pendientes, en orden `created_at ASC, id ASC`. La vista previa devuelve el
conteo y la lista exacta de seleccionados. La solicitud de venta sigue requiriendo confirmación explícita. Los
items de lote sin `seleccion` y las ventas de un solo animal mantienen el comportamiento previo. No se escriben
identificadores ni se actualizan filas de `cattle_livestock`.

## Orden de despliegue

1. Base de datos.
2. Workflows de n8n.
3. Frontend, solo cuando las partes 1 y 2 estén completadas y verificadas.

## Parte 1 — base de datos

Usa una conexión autorizada y conserva la salida de cada verificación. Sustituye los placeholders; no incluyas
credenciales en el repositorio ni en logs compartidos.

1. **Respaldo previo:** crea un backup custom-format antes de cualquier cambio:

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   ```

2. **Estado previo:** verifica la huella de la función 096 y guarda las huellas de datos:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=before \
     -f 097_state_check.sql
   ```

   Debe reportar `STATE OK: before`; la definición previa esperada es
   `d3c1fadef0b7d5e9c188acda08df85fb`. Detente ante cualquier diferencia.

3. **Dry run:** sin `-v apply=true`, el script ejecuta la migración dentro de una transacción que revierte:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 \
     -f 097_fifo_sale_unidentified.sql
   ```

4. **Aplicación:** solo después de comprobar el dry run, aplica el cambio:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true \
     -f 097_fifo_sale_unidentified.sql
   ```

5. **Estado aplicado:** calcula primero mediante ensayo la huella MD5 de la definición final, actualiza el
   placeholder `TO BE FILLED AFTER REHEARSAL` en `097_state_check.sql` con ese valor verificado y revisado, y
   ejecuta:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=applied \
     -f 097_state_check.sql
   ```

   Debe reportar `STATE OK: applied`. Compara las huellas de datos con las del paso 2; deben permanecer idénticas.
   No inventes ni estimes la huella. Si no se dispone de una base de ensayo para obtenerla, detén el despliegue.

6. **Prueba funcional de producción:** limita toda verificación con datos de producción a la empresa 3. Usa
   preferentemente una transacción que termine en `ROLLBACK`; si se usa un animal de prueba, elimínalo mediante el
   procedimiento autorizado de limpieza y verifica que no queden solicitudes ni movimientos de prueba. Nunca
   escribas datos de prueba en la empresa 5 ni en la empresa 6. Comprueba: preview FIFO de la categoría/lote y
   cantidad solicitados; aprobación de la orden con `sp_resolver_autorizacion`; y una fila de ingreso en
   `cattle_sale_income` para cada ID elegido. No uses animales reales ni cuentas reales como datos de prueba.

### Pruebas SQL de ensayo

Ejecuta `097_tests.sql` únicamente en LOCAL o en una base de ensayo con esquema compatible. El archivo crea
compañías, usuarios y animales sintéticos dentro de una transacción, y termina en `ROLLBACK`; no lo ejecutes sobre
empresas reales. Debe cubrir orden FIFO y desempate por ID, exclusiones, errores de validación y disponibilidad,
aislamiento y membresías de solo lectura, solicitudes consecutivas sin repetición, regresiones de venta por lote y
por identificador, payload, preview sin escrituras, regla de guía de 096 y aprobación end-to-end.

### Protección contra drift

El guard compara la definición viva contra el MD5 de 096 antes de reemplazarla. Si difiere, detén el despliegue y
reconstruye la migración desde la definición viva revisada. No omitas ni neutralices el guard para continuar.

## Parte 2 — workflows de n8n

Con la base de datos aplicada y `097_state_check.sql -v expect=applied` verificado, sigue el procedimiento de
n8n 2.x:

1. **Respaldo:** abre cada workflow de Chat, WhatsApp y MCP Server Cattle en producción; selecciona **⋯ →
   Download** y guarda cada export fuera del repositorio con permisos `600`.
2. **Comparación con `origin/main`:** compara el respaldo y el export de `main` por nombre de nodo, `parameters`
   y `connections`. Calcula la huella del respaldo con `python3 -I ~/node_fingerprints.py <archivo>` y detente si
   no coincide con la huella previa esperada. Si hay diferencias, resuélvelas antes de continuar.
3. **Comparación con `origin/develop`:** registra los cambios esperados. En los dos agentes debe cambiar solo
   `AI Agent.parameters.options.systemMessage`; en MCP Server Cattle, las descripciones y la descripción de
   `items_json` de `preview_livestock_sale_order` y `request_livestock_sale_order`. Confirma que no cambien
   conexiones, credenciales, `webhookId`, `typeVersion` ni `settings`. Los IDs internos de nodos no son
   significativos.
4. **Importar y publicar:** en el editor de producción, usa **⋯ → Import from file…** sobre cada workflow
   existente, pulsa **Save** y después **Publish**. No uses `n8n import:workflow`.
5. **Verificar publicación:** descarga nuevamente los tres workflows y compáralos con `origin/develop`; el
   resultado esperado es `No differences.`. No consideres publicado un workflow sin coincidencia exacta.
6. **Comportamiento:** exclusivamente en la empresa 3 y con datos sintéticos, pide una venta FIFO de una cantidad
   determinada de animales no bovinos sin identificadores. Confirma que el agente llama primero al preview,
   muestra la cantidad y lista devueltas y espera un «Sí» antes de invocar el request. Comprueba que bovinos y
   especies desconocidas no usan FIFO y que los bovinos siguen las reglas de identificadores y guía. Ejecuta las
   pruebas dentro de una transacción que se revierta o limpia el animal de prueba al terminar. No uses las
   empresas 5 o 6.
7. **Rollback de workflows:** si falla la comparación o la prueba, vuelve a importar los exports respaldados,
   pulsa **Save** y **Publish**, y confirma por re-descarga que coinciden con los respaldos.

## Parte 3 — frontend

Despliega el frontend después de verificar las partes 1 y 2. La lista y el modal de aprobación deben mostrar
«Sin identificador · selección automática», categoría, lote e ID corto para cada solicitud FIFO.

## Rollback de base de datos

Después de respaldar y confirmar el estado aplicado, revierte en modo dry run y luego aplica:

```sh
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -f 097_rollback.sql
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true -f 097_rollback.sql
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=rolled_back \
  -f 097_state_check.sql
```

La última comprobación debe reportar `STATE OK: rolled_back` y recuperar la huella 096
`d3c1fadef0b7d5e9c188acda08df85fb`; las huellas de datos deben continuar idénticas.
