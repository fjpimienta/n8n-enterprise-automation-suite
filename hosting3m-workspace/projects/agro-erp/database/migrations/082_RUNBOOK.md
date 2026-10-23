# Runbook — Palma Fase 2b, Etapa 1: bloquear las tools de ganadería en empresas de palma (082 + n8n)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *Este cambio no toca el frontend; aun así el merge va al final, por la regla.*

**Por qué es urgente:** el 2026-10-21, con la empresa 10 (palma, de pruebas) activa, el Chat Web llamó a
`register_ranch_expense` con `tenant_id: 10` y guardó en `cattle_expenses` el gasto `3f294c48-c509-42bd-8d3e-2dcfdf6b7913`
($1,300, "MANTENIMIENTO"). La empresa 7 (cliente real de palma) está expuesta a lo mismo.

**Qué cambia:**
- Base de datos (082): `fn_reject_palm_company(id_company)` lanza `P0094` ("Esta empresa es de palma; usa el registro
  de palma…") si la empresa es de palma (`fn_company_business_domain`, 081); en otro caso devuelve `true`.
- `v6/MCP Server Cattle`: 26 de las 29 tools la llaman como primera condición del `WHERE` (escrituras y lecturas).
  Sin tocar: `get_table_metadata` (el prompt la prohíbe) y las dos de órdenes de venta (no reciben empresa: buscan
  animales en todas las empresas del usuario, y una empresa de palma no tiene animales).
- `v6/ai/chat cattle` y `v6/WhatsApp Agent Catlte`: el dominio de la empresa entra al contexto verificado
  (`Resolver Empresa Chat` / `Get User Role` + `Resolver Tenant`). Con una empresa de palma el workflow **no llama al
  agente**: un IF `Es Empresa de Palma` responde un mensaje fijo (Chat Web: `code: PALM_COMPANY`; WhatsApp: por
  `Send Message Tenant`). La regla del prompt y la 082 quedan como defensa en profundidad. Motivo: en LOCAL, con solo
  la regla del prompt, el modelo la siguió en 1 de 3 mensajes (2026-10-23).

⚠️ **Orden estricto: base de datos → n8n.** Si las tools llegan antes que la función, **todas** las tools de ganadería
fallan ("function fn_reject_palm_company does not exist"). Por la misma razón, el rollback de la base nunca borra la
función: la deja devolviendo `true`.

## 0. Preparación (local)

- md5 esperados:

  | Archivo | md5 |
  |---|---|
  | `082_reject_palm_in_livestock_tools.sql` | `69008b6b282e63973620f9d1c748d437` |
  | `082_tests.sql` | `f0eaa890ef41bbd204af965e401b11f6` |
  | `082_rollback.sql` | `276e7d6255e2488f46b9184a57af72cd` |
  | `082_state_check.sql` | `1fd666ec72fca3b9b4cacd4ac6cd537c` |

- Script de huellas: el del repo (`cp node_fingerprints.py ~/node_fingerprints.py`); ahora también cubre las tools,
  el `systemMessage` de los agentes y el tipo de endpoint MCP (nunca la URL).
- Anotar la línea base (solo lectura) para comparar al final:

  ```sql
  SELECT tenant_id, count(*) FROM cattle_expenses WHERE tenant_id IN (7, 10) GROUP BY 1;
  ```

## 1. Base de datos: migración 082 (VPS, `n8n-enterprise-db`, `hosting3m_db`)

```bash
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```

1. **Respaldo:** `docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc hosting3m_db > /root/backups/hosting3m_db_pre082_$(date +%F_%H%M).dump`
2. **Copiar** `082_*` a `/root/m082/`, verificar md5 contra el paso 0 y `docker cp /root/m082 n8n-enterprise-db:/tmp/m082`.
3. **Antes:** `$P -v expect=before -f /tmp/m082/082_state_check.sql` → `082 state check (before): OK`. Anotar las
   4 huellas (`crud_models`, `companys_data`, `cattle_expenses_data`, `agri_expenses_data`).
4. **Dry run:** `$P -f /tmp/m082/082_reject_palm_in_livestock_tools.sql` → `082: OK` y `DRY RUN`.
5. **Pruebas:** `$P -f /tmp/m082/082_tests.sql` → `11 | 0 | 11` y `everything rolled back`. Toca la 7 solo en lectura.
6. **Aplicar:** `$P -v apply=true -f /tmp/m082/082_reject_palm_in_livestock_tools.sql` → `082 COMMITTED`.
7. **Después:** `$P -v expect=applied -f /tmp/m082/082_state_check.sql` → `applied: OK`, las 4 huellas iguales a 1.3.

**Rollback de la base:** `$P -f /tmp/m082/082_rollback.sql` (dry run), luego con `-v apply=true`, y
`082_state_check.sql -v expect=rolled_back`. La función queda devolviendo `true`: las tools vuelven a comportarse como
antes de 082 sin tocar n8n. **Nunca** `DROP FUNCTION` mientras las tools la llamen.

## 2. n8n (desde el editor de producción, en este orden)

Para cada workflow: (a) descargar el export de producción como respaldo y sacar la huella "antes" — **detenerse si no
coincide**; (b) importar desde el editor el JSON de `workflows/09-MCP-Agent-Cattle/v6/` sobre el mismo workflow (mismo
id); revisar credenciales y que el endpoint MCP siga en producción; **guardar y Publish**; (c) descargar de nuevo y
verificar la huella "después". Justo después de publicar, un webhook puede responder 404 unos segundos.

### 2.1 `v6/MCP Server Cattle` (`pJ3CEaO70QEiGL0C`)

Antes:

```
   workflow pJ3CEaO70QEiGL0C v6/MCP Server Cattle active=True   (versionId cambia)
     MCP Server Cattle      mcp path=v6/cattle-management
     tool cancel_pending_request         06070b2df24cd43367edd0ad4fed3693
     tool cancel_pending_request         queryReplacement 4aa7069d07bf48bc1a42da5bb6442f85
     tool count_livestock                427585a68eb7fb946ed371123696b107
     tool count_livestock                queryReplacement 71d29e3ba1f21ef385eda5411455830b
     tool find_calf_by_dam               773e76ca43cc3b5f0e26e63e9e26d1c8
     tool find_calf_by_dam               queryReplacement 11bf3d069d11742ccdc688f324fdb142
     tool find_livestock_by_criteria     958e5d3818f0bf3a56fe6849ffb912e7
     tool find_livestock_by_criteria     queryReplacement 89f15c080ab4148cba7169d5486c6079
     tool get_livestock_info             bc9d8b3ca1a1234c7c323ae81a1102a1
     tool get_livestock_info             queryReplacement c6fa81acff47aaa2a148ce0e7701a8b3
     tool get_table_metadata             118b35f579e0447a29c071114a86f7ac
     tool get_table_metadata             queryReplacement 15b6381801f350fbc7aa8ae9e11adf60
     tool list_lots                      ab15d1b1d312df7d086f1d51a48b0488
     tool list_lots                      queryReplacement 79c7f7cba6827b9d5e7965b5d3026ce8
     tool list_pending_requests          1a2bd0b02b81fcac01b0a127f6bd8ba2
     tool list_pending_requests          queryReplacement 0b5e80a5073a2a1dd62f1f536a199ee3
     tool log_breeding_event             c271dba70a72184b12ba68e32cfeb925
     tool log_breeding_event             queryReplacement fed32b41e4093852ea94e891fa1ca3e0
     tool log_castration_event           825737c00837e80c79e04d66eb8bc9e7
     tool log_castration_event           queryReplacement f599bbfb7a0b3380f197016eace8cbdf
     tool log_cattle_weight              7d3c364d84f8a540e9e63cc4a493feff
     tool log_cattle_weight              queryReplacement a20ad717c7b38daddcac692bf9b12d9b
     tool log_deworming_event            6a281fecfe1e867ac297a9e4ef5f5732
     tool log_deworming_event            queryReplacement fa3f8e89391a4a04220ad348fd7fc38a
     tool log_health_event               7ae6f6dcf555a371413fddb3624910c9
     tool log_health_event               queryReplacement 9bd86e9f3c6b9dc9750063ab73532a1b
     tool log_mortality_event            944ffb60f2671ce376a3487a535aa57f
     tool log_mortality_event            queryReplacement c92b615af8480b0e17ce2a6a2fd11dab
     tool log_palpation_event            96b0134cff706e361dd8f474eb5eae8e
     tool log_palpation_event            queryReplacement 99fd65bba23b10727fbd733b49ef8536
     tool log_palpation_event_batch      1b0e25c9574b93df46d963f48c846789
     tool log_palpation_event_batch      queryReplacement c6cb0fa39219e8bef2ced0aa5d646930
     tool log_supplement_event           cffa3cc76ddfaef511d5316580b14087
     tool log_supplement_event           queryReplacement e7c91b8fdfd8b2762db872f9f3a91722
     tool log_vaccination_event          f78c78a4c25aadf99b6839cb2b5d39c3
     tool log_vaccination_event          queryReplacement 10933656f73706f457557d1605224414
     tool log_weaning_event              520dc820e4c9bb52a257c7ac68051cd9
     tool log_weaning_event              queryReplacement 92004fc3e9445d9dd9edd7bb9db56d29
     tool move_livestock                 a4a51b652377edb0033cb110163f7589
     tool move_livestock                 queryReplacement b14bd923c88c82f77be363ab059a0296
     tool preview_livestock_sale_order   34f729ea4ec38c8db62b4676a6f8712d
     tool preview_livestock_sale_order   queryReplacement 7c51790884c0f3f4a138b0d1b7fb23f5
     tool register_birth_event           da0d75344eb8391aaae418dce25e0c53
     tool register_birth_event           queryReplacement 3b8b071e597aca303be4cda6f486ae95
     tool register_livestock_purchase    1c83816abbb574e44ae20e742d159f01
     tool register_livestock_purchase    queryReplacement 273f8deb62802e01d7485d9c911da762
     tool register_ranch_expense         2111774077d6748b21b3784ece3fab6b
     tool register_ranch_expense         queryReplacement fd4d8445077c439ad57b08edb80a58f0
     tool request_livestock_sale         d562a27826bde00ebffa30939bcde4bd
     tool request_livestock_sale         queryReplacement d9e10011dab26fb8cfcf2da9581d19bb
     tool request_livestock_sale_order   503a5e30b0c95dfcefc7afd3a756a0f0
     tool request_livestock_sale_order   queryReplacement 7c51790884c0f3f4a138b0d1b7fb23f5
     tool review_pending_request         a24fdb78364cd01e8a1996c5f82f14b0
     tool review_pending_request         queryReplacement bc57d43201fb1ebdcd921da5dc735f78
     tool update_livestock_tag           93f0edb13ba08adb07d4229f0de165a8
     tool update_livestock_tag           queryReplacement 4157bd025d28c13bef4b7ea137d050a2
     tool void_event                     df87c4599a7be8854eecf2eb9a1fdc41
     tool void_event                     queryReplacement 76f666cc25ae7eb123ce229b902b1584
     postgres nodes=0 credential names=[]
     postgres tools=29 credential names=['Postgres account']
```

Después (cambian las 26 líneas `tool …` de consulta; ningún `queryReplacement`):

```
   workflow pJ3CEaO70QEiGL0C v6/MCP Server Cattle active=True   (versionId cambia)
     MCP Server Cattle      mcp path=v6/cattle-management
     tool cancel_pending_request         b1d28c6d12471bc1f910ced72f814f67
     tool cancel_pending_request         queryReplacement 4aa7069d07bf48bc1a42da5bb6442f85
     tool count_livestock                98e585153c7bc36a40eff2f08a2b541e
     tool count_livestock                queryReplacement 71d29e3ba1f21ef385eda5411455830b
     tool find_calf_by_dam               bbd0b4899f7072664bf11cd7e3c9bfa2
     tool find_calf_by_dam               queryReplacement 11bf3d069d11742ccdc688f324fdb142
     tool find_livestock_by_criteria     3e9741a658f151c16b51ae6d6bd945d5
     tool find_livestock_by_criteria     queryReplacement 89f15c080ab4148cba7169d5486c6079
     tool get_livestock_info             93707cfcaac164e4fc352fc2ea4dfb83
     tool get_livestock_info             queryReplacement c6fa81acff47aaa2a148ce0e7701a8b3
     tool get_table_metadata             118b35f579e0447a29c071114a86f7ac
     tool get_table_metadata             queryReplacement 15b6381801f350fbc7aa8ae9e11adf60
     tool list_lots                      6a387e92886448d165d3dd10a8b8208f
     tool list_lots                      queryReplacement 79c7f7cba6827b9d5e7965b5d3026ce8
     tool list_pending_requests          a0f4f597136e29e53ecd3cdf6128f5f7
     tool list_pending_requests          queryReplacement 0b5e80a5073a2a1dd62f1f536a199ee3
     tool log_breeding_event             c1c28edba9222a36a715a556bb9f2596
     tool log_breeding_event             queryReplacement fed32b41e4093852ea94e891fa1ca3e0
     tool log_castration_event           7c601f68cd77fcb65c748bfd37a56f37
     tool log_castration_event           queryReplacement f599bbfb7a0b3380f197016eace8cbdf
     tool log_cattle_weight              fc1823b2d4c77cdc934ec342ebe517f8
     tool log_cattle_weight              queryReplacement a20ad717c7b38daddcac692bf9b12d9b
     tool log_deworming_event            c0b553efc3c671911cfaabde483eb31a
     tool log_deworming_event            queryReplacement fa3f8e89391a4a04220ad348fd7fc38a
     tool log_health_event               47f6516382f715daf1b3d97a7bd4e4eb
     tool log_health_event               queryReplacement 9bd86e9f3c6b9dc9750063ab73532a1b
     tool log_mortality_event            60cbbac72bfcd7c48dfc071577c8237e
     tool log_mortality_event            queryReplacement c92b615af8480b0e17ce2a6a2fd11dab
     tool log_palpation_event            3b6db83f20b888e773dc00ef4b1d807e
     tool log_palpation_event            queryReplacement 99fd65bba23b10727fbd733b49ef8536
     tool log_palpation_event_batch      e3175fe929a954699375cf8ddb5d4e83
     tool log_palpation_event_batch      queryReplacement c6cb0fa39219e8bef2ced0aa5d646930
     tool log_supplement_event           b89ba07e70f4eb3185252db89e11e2ca
     tool log_supplement_event           queryReplacement e7c91b8fdfd8b2762db872f9f3a91722
     tool log_vaccination_event          b430d0c3e4ec97d88e2973cbac375921
     tool log_vaccination_event          queryReplacement 10933656f73706f457557d1605224414
     tool log_weaning_event              b2252fd3c11c6f25a00256a0ae72f44f
     tool log_weaning_event              queryReplacement 92004fc3e9445d9dd9edd7bb9db56d29
     tool move_livestock                 22e4fb7566b7172043bbc7c18104e6f4
     tool move_livestock                 queryReplacement b14bd923c88c82f77be363ab059a0296
     tool preview_livestock_sale_order   34f729ea4ec38c8db62b4676a6f8712d
     tool preview_livestock_sale_order   queryReplacement 7c51790884c0f3f4a138b0d1b7fb23f5
     tool register_birth_event           2ffcbb335a716cc72994149e4f6fb27b
     tool register_birth_event           queryReplacement 3b8b071e597aca303be4cda6f486ae95
     tool register_livestock_purchase    809927b6b51d4cf0035dbc04d0f60c8e
     tool register_livestock_purchase    queryReplacement 273f8deb62802e01d7485d9c911da762
     tool register_ranch_expense         e01f2a40bce77a5a665484a8313615fd
     tool register_ranch_expense         queryReplacement fd4d8445077c439ad57b08edb80a58f0
     tool request_livestock_sale         ec069d501fb70aae300f8dd2bd0ffccb
     tool request_livestock_sale         queryReplacement d9e10011dab26fb8cfcf2da9581d19bb
     tool request_livestock_sale_order   503a5e30b0c95dfcefc7afd3a756a0f0
     tool request_livestock_sale_order   queryReplacement 7c51790884c0f3f4a138b0d1b7fb23f5
     tool review_pending_request         75562572667b204e55ee50ee9e05031e
     tool review_pending_request         queryReplacement bc57d43201fb1ebdcd921da5dc735f78
     tool update_livestock_tag           8dbce3f654469b528c0883f3fbd5c4d4
     tool update_livestock_tag           queryReplacement 4157bd025d28c13bef4b7ea137d050a2
     tool void_event                     1e551806e4b3e4232e23032b642f4da2
     tool void_event                     queryReplacement 76f666cc25ae7eb123ce229b902b1584
     postgres nodes=0 credential names=[]
     postgres tools=29 credential names=['Postgres account']
```

### 2.2 `v6/ai/chat cattle` (`RM60Dm0e3r03dvnp`)

Antes:

```
   workflow RM60Dm0e3r03dvnp v6/ai/chat cattle active=True   (versionId cambia)
     AI Agent               systemMessage cc83ed83c9fe37799b2eb9544615afa7
     MCP Cattle Management  endpoint=production
     Resolver Empresa Chat  5743ec61a14c2e18c2e5db837407b6b3
     Resolver Empresa Chat  queryReplacement c1f1d860410cc58dd901b5101c742198
     Simple Memory          040ff1f0493f6e031750e4c100fa6249
     webhook path=v6/ai/chat-cattle webhookId=90388e0d-f87c-47ad-a744-43c2de38cfc1
     postgres nodes=1 credential names=['Postgres account']
     connections 99c499ecc9059a69026b95470b084efa
```

Después: `AI Agent` (`systemMessage` con dominio y regla de palma; texto y contexto con `.first()`), `Resolver Empresa
Chat`, `Simple Memory` (clave de sesión con `.first()`), los nodos nuevos `Es Empresa de Palma` y `Respond Empresa
Palma`, y `connections` (`Empresa Valida` → `Es Empresa de Palma` → palma: `Respond Empresa Palma` / otra: `AI Agent`).
`endpoint=production` debe seguir igual:

```
   workflow RM60Dm0e3r03dvnp v6/ai/chat cattle active=True   (versionId cambia)
     AI Agent               systemMessage 85c4ee445503c04625d6886fd58b0ccf
     Es Empresa de Palma    d75238bf98c027f9ee98c8d0c2ec6fa3
     MCP Cattle Management  endpoint=production
     Resolver Empresa Chat  9df861e269cf4d478aae9d9acd49a846
     Resolver Empresa Chat  queryReplacement c1f1d860410cc58dd901b5101c742198
     Respond Empresa Palma  796f51f9e8d09d4f00630fe66e88850a
     Simple Memory          fb387e5d00b1c90ef9bd1b9f0d2f4c6f
     webhook path=v6/ai/chat-cattle webhookId=90388e0d-f87c-47ad-a744-43c2de38cfc1
     postgres nodes=1 credential names=['Postgres account']
     connections acd9dafb7830b2c1ee4befcdc1a2fd24
```

### 2.3 `v6/WhatsApp Agent Catlte` (`lqgFIeTbSdPRT8zz`)

Antes:

```
   workflow lqgFIeTbSdPRT8zz v6/WhatsApp Agent Catlte active=True   (versionId cambia)
     AI Agent               systemMessage a1f7d03e3f57a452bbe4185282146d54
     Get User Role          61242b73d76aae06f523479ad7158159
     Get User Role          queryReplacement e4fd0c0f9b459349ccfbb8eecef52cc8
     MCP Client             endpoint=production
     Resolver Tenant        cdccc186a5a57adafcb11c5d4bc7dd71
     Set Prompt Final       abab95d40a936e2f91f7e568c7f692e2
     Simple Memory          118c3897bedffc391ba4a837c8a6d013
     postgres nodes=4 credential names=['Postgres account']
     connections b5b01b902d2134cd3d0190fc9dc6a0a8
```

Después: `AI Agent` (`systemMessage` con dominio y regla; texto y contexto con `.first()`), `Get User Role`,
`Resolver Tenant`, los nodos nuevos `Es Empresa de Palma` y `Set - Mensaje Empresa Palma`, y `connections`
(`Set Prompt Final` → `Es Empresa de Palma` → palma: `Set - Mensaje Empresa Palma` → `Send Message Tenant` / otra:
`AI Agent`):

```
   workflow lqgFIeTbSdPRT8zz v6/WhatsApp Agent Catlte active=True   (versionId cambia)
     AI Agent               systemMessage e8d5ba2db1b1c4766b06fd67d9d17016
     Es Empresa de Palma    cf24c296cb71c68d6545fcc1cc2eaa4d
     Get User Role          c75f2321f0c310aa0855febbccef8097
     Get User Role          queryReplacement e4fd0c0f9b459349ccfbb8eecef52cc8
     MCP Client             endpoint=production
     Resolver Tenant        4c191ab2f0af0f03f50b5023261e969a
     Set - Mensaje Empresa Palma b6c0bc3ce30a4b92c821a22fb7625b1a
     Set Prompt Final       abab95d40a936e2f91f7e568c7f692e2
     Simple Memory          118c3897bedffc391ba4a837c8a6d013
     postgres nodes=4 credential names=['Postgres account']
     connections 7483838972e41c285437399beedceaf5
```

⚠️ **Por qué `.first()`:** con el IF entre el nodo anterior y `AI Agent`, n8n ya no resuelve `$('Nodo').item` cuando el
agente vuelve a evaluar sus expresiones después de llamar a una tool (en LOCAL, 2026-10-23: "Key parameter is empty"
en `Simple Memory` y "No prompt specified" en `AI Agent`). Cada ejecución procesa un solo mensaje, así que `.first()` es
equivalente. Si en producción una conversación de ganadería que usa una tool responde vacío, revisar estas expresiones
antes que nada.

**Rollback de n8n:** reimportar desde el editor el export del paso (a) de cada workflow y publicar; verificar que la
huella vuelve a la de "antes". Cada workflow se puede revertir por separado.

## 3. Frontend

No hay cambios de frontend. Merge a `main` solo después de 1 y 2 verificados.

## 4. Pruebas en producción (por el canal real; nunca desde el panel de chat del editor)

1. **Chat Web, empresa 10 (palma), ADMIN:** "Compré material para la bomba de agua por 1,300, incluye mano de obra".
   Esperado: en 1–2 s, el mensaje fijo "Esta empresa es de palma…" (respuesta con `code: PALM_COMPANY`); en n8n la
   ejecución no pasa por `AI Agent`.
2. **Chat Web, empresa 10:** "¿Cuántos animales hay?" → mismo aviso, sin conteo.
3. **Chat Web, empresa 3 (ganadería):** "¿Cuántos animales hay en total?", luego en la misma conversación "¿Y de esos
   cuántos son becerras?" (prueba la memoria después de una tool), y una consulta de arete de prueba → igual que hoy, sin
   respuestas vacías.
4. **WhatsApp** (teléfono con membresía en la 10 y en la 3): mensaje nombrando "Plantación de Pruebas" con un gasto →
   aviso de palma; mensaje nombrando "Rancho El Palomar" con una consulta → igual que hoy.
5. **Verificación (solo lectura):** la consulta del paso 0 da los mismos conteos (ninguna fila nueva en
   `cattle_expenses` para la 7 ni la 10); `n8n_error_logs` sin filas nuevas de `v6/MCP Server Cattle` ni de los chats.

## 5. Rollback completo

n8n (2) y/o base (1), en cualquier orden: la base revertida deja la función en `true` y n8n revertido deja de
llamarla. Nunca borrar la función.

## 6. Datos del incidente

- El gasto `3f294c48-…` ($1,300) de `cattle_expenses` de la empresa 10 (de pruebas) **se conserva como evidencia**
  del incidente (decisión del dueño, 2026-10-23). En la línea base del paso 0 cuenta como 1 fila de la empresa 10.
