> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (migración 096 de base de datos verificada y cambio de n8n publicado y verificado).
> `main` publica automáticamente los frontends por Plesk. No publiques esta versión antes de completar las dos partes.

# Runbook: guía de tránsito según especie

Este runbook despliega el cambio de instrucciones del agente de venta. La vista previa solicita guía de tránsito únicamente cuando la regla de cumplimiento bovino la requiere.

## Alcance y partes

1. **Base de datos — migración 096:** ya aplicada en producción el 2026-11-03 y verificada. Antes del despliegue, comprueba el estado con `096_state_check.sql -v expect=applied`. Si el resultado no confirma `applied`, detente.
2. **n8n — este cambio:** reemplaza y publica los tres workflows indicados en este runbook; completa las verificaciones de contenido y comportamiento.
3. **Panel — PR posterior:** mostrar claramente **Sin guía** en el panel de autorizaciones. No forma parte de este despliegue. `v6_Notificacion_Autorizaciones.json` ya presenta **Sin guía** y no se modifica en este cambio.

No continúes con `main` hasta que las partes 1 y 2 estén verificadas. La parte 3 se dará seguimiento por separado.

## Workflows y nodos incluidos

| Workflow | Nodos que cambian |
|---|---|
| `v6_ai_chat_cattle.json` | `AI Agent` — únicamente `parameters.options.systemMessage` |
| `v6_WhatsApp_Agent_Cattle.json` | `AI Agent` — únicamente `parameters.options.systemMessage` |
| `v6_MCP_Server_Cattle.json` | `preview_livestock_sale_order` y `request_livestock_sale_order` — descripciones de herramientas y descripción de `items_json` en `queryReplacement` |

No cambies otros nodos, parámetros, conexiones ni credenciales. `AI Agent Palma` debe permanecer intacto. Los cambios de prompt conservan el prefijo `=` y todas las expresiones `{{ }}`.

## Despliegue en n8n 2.x

1. **Precondiciones:** el cambio debe estar integrado en `develop` y CI debe estar en verde. Confirma la parte 1 con `096_state_check.sql -v expect=applied`. No publiques cambios de workflow en `main` antes de importarlos y verificarlos en n8n.
2. **Respaldo:** en producción, abre cada workflow de la tabla, selecciona **⋯ → Download** y guarda cada export fuera del repositorio. Usa nombres distinguibles, por ejemplo `chat-produccion-antes.json`, `whatsapp-produccion-antes.json` y `mcp-produccion-antes.json`; limita los permisos de cada archivo a `600`.
3. **Comparación con `origin/main`:** compara cada respaldo con su export correspondiente de `origin/main`, por nombre de nodo, `parameters` y `connections`. El resultado esperado es `No differences.`. Calcula además la huella de cada respaldo con `python3 -I ~/node_fingerprints.py /ruta/al/respaldo.json` y detente si no coincide con la huella "antes" registrada para ese workflow. Si hay diferencias, detente y resuélvelas antes de continuar.
4. **Comparación con `origin/develop`:** compara cada respaldo con el export correspondiente de `origin/develop` usando el mismo procedimiento. Registra los parámetros exactos que cambian en cada nodo y cualquier cambio de conexión esperado; deben cambiar solo los nodos y parámetros enumerados arriba, sin cambios de conexión. Confirma también que `credentials` de cada nodo, `webhookId`, `typeVersion` de cada nodo y `settings` del workflow no cambien. Los `id` de los nodos pueden variar en una importación y no son significativos.

   Usa este comparador para cada par de archivos (respaldo y candidato):

   ```sh
   python3 - /ruta/al/respaldo.json /ruta/al/candidato.json <<'PY'
   import json
   import sys
   from pathlib import Path

   def load(path):
       return json.loads(Path(path).read_text())

   before, after = map(load, sys.argv[1:3])
   before_nodes = {node["name"]: node.get("parameters", {}) for node in before["nodes"]}
   after_nodes = {node["name"]: node.get("parameters", {}) for node in after["nodes"]}
   changed_nodes = sorted(
       name for name in before_nodes.keys() | after_nodes.keys()
       if before_nodes.get(name) != after_nodes.get(name)
   )
   before_connections = before.get("connections", {})
   after_connections = after.get("connections", {})
   changed_connections = sorted(
       name for name in before_connections.keys() | after_connections.keys()
       if before_connections.get(name) != after_connections.get(name)
   )
   if not changed_nodes and not changed_connections:
       print("No differences.")
   else:
       print("Nodes with changed parameters:", changed_nodes)
       for name in changed_connections:
           print(f"Connection changes for {name}:")
           print("  before:", json.dumps(before_connections.get(name), sort_keys=True))
           print("  after: ", json.dumps(after_connections.get(name), sort_keys=True))
   PY
   ```

   For the `develop` comparison, the expected changed nodes are `AI Agent` in each agent workflow and `preview_livestock_sale_order` plus `request_livestock_sale_order` in the MCP server workflow. Investigate any additional node or connection change before proceeding.
5. **Importación y publicación:** para cada workflow, abre el editor de producción y selecciona **⋯ → Import from file…**. Importa el JSON de `develop` en el workflow existente, conserva el mismo `id` y `webhookId`, pulsa **Save** y luego **Publish**. Repite con Chat, WhatsApp y MCP Server. No uses `n8n import:workflow`: puede desactivar el workflow y cambiar el `versionId`.
6. **Verificación de publicación:** descarga nuevamente cada workflow publicado y compáralo con el JSON de `origin/develop` usando el comparador del paso 4. El resultado esperado es `No differences.`. No consideres publicado un workflow si la comparación no coincide.
7. **Verificación funcional — exclusivamente empresa 3 (Rancho El Palomar), a través del chat:** utiliza datos de prueba y sustituye los placeholders; no realices estas pruebas en otra empresa.
   - Inicia sesión con `[EMAIL_DE_PRUEBA_EMPRESA_3]` y solicita una orden, por ejemplo: “vende el borrego `[ARETE_BORREGO_DE_PRUEBA]`”. El agente no debe pedir guía de tránsito y debe crear una solicitud pendiente después de la confirmación explícita.
   - Solicita la venta de un bovino de prueba `[ARETE_BOVINO_DE_PRUEBA]` sin proporcionar guía. El agente debe llamar primero a la vista previa y, si esta devuelve `Falta la guía de tránsito`, pedir la guía solo para ese grupo. Proporciona `[GUIA_BOVINO_DE_PRUEBA]` y confirma que la vista previa se vuelve a llamar con la guía incluida.
   - Verifica que la aprobación de una venta bovina de prueba sin arete oficial `[IDENTIFICADOR_BOVINO_SIN_ARETE_DE_PRUEBA]` siga siendo rechazada.

   Revisa las ejecuciones recientes de esos tres casos y confirma la ruta esperada: vista previa antes de preguntar por una guía bovina, y creación de la solicitud solo después de la confirmación del usuario. No uses datos reales de huéspedes, productores o animales fuera de los registros de prueba de la empresa 3.
8. **Rollback:** si falla la comparación o una prueba, vuelve a importar en el editor el respaldo del paso 2 para cada workflow afectado, pulsa **Save** y **Publish**, y verifica que el export publicado vuelva a coincidir con el respaldo.
9. **Release:** solo después de verificar las partes 1 y 2 puede continuar el proceso de release hacia `main`. La parte 3 se entrega mediante su PR posterior; este runbook no la despliega.
