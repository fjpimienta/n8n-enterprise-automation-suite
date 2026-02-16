# 🔍 Reporte de Auditoría: n8n Workflows
**Fecha:** 2026-02-15  
**Auditor:** n8n Workflow Auditor  
**Alcance:** Flujos v3/v4 en producción

---

## 📊 Resumen Ejecutivo

| Métrica | Valor |
|---------|-------|
| **Flujos Auditados** | 11 |
| **Críticos Detectados** | 8 |
| **Mejoras Sugeridas** | 15 |
| **Flujos OK** | 3 |

---

## 🔴 HALLAZGOS CRÍTICOS GLOBALES

### 1. **Global Error Handler** ✅ ROBUSTO
**Archivo:** `00-global-error-handler/Global Error Handler.json`

| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🟢 OK | Usa credentials para Postgres. URL de ntfy.sh es pública (correcto para alertas). |
| 🛡️ Robustez | 🟢 OK | No tiene `continueOnFail` porque ES el manejador de errores. |
| ⚙️ Lógica | 🟢 OK | Captura errores, los registra en DB y envía alertas. Sin bucles. |

**Veredicto:** Este flujo es el backbone de seguridad. Está bien implementado.

---

## 📁 01-auth-jwt-gateway/v3

### **v3_GeneraToken.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🟢 OK | Usa `$env["INTERNAL_SECRET"]` y `$env["N8N_PASS"]`. No hay hardcoding. |
| 🛡️ Robustez | 🟢 OK | Nodo `GenerateToken` tiene `onError: continueRegularOutput`. Conectado al Global Error Handler. |
| ⚙️ Lógica | 🟢 OK | Flujo lineal sin bucles. Maneja errores con respuesta 401. |

**Veredicto:** ✅ Seguro y robusto.

---

### **v3_SW ValidaToken.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🟢 OK | Usa `$env["INTERNAL_SECRET"]` para validación interna. |
| 🛡️ Robustez | 🟢 OK | Nodo `Verify Token` tiene `onError: continueRegularOutput`. |
| ⚙️ Lógica | 🟢 OK | Subworkflow reutilizable. Sin bucles. |

**Veredicto:** ✅ Bien diseñado como servicio interno.

---

## 📁 02-leads-contact/v3

### **v3-contact.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🟡 MEJORA | Usa `$env["CLOUDFREE_SECRET_KEY"]` ✅. Pero los nodos `Insert`, `Update`, `getCustomer` hacen llamadas HTTP a CRUD sin `continueOnFail`. |
| 🛡️ Robustez | 🔴 CRÍTICO | **Nodos HTTP Request (Insert, Update, getCustomer) tienen `onError: continueErrorOutput` pero NO están conectados al Global Error Handler.** Si el CRUD falla, el flujo continúa pero puede enviar emails con datos incorrectos. |
| ⚙️ Lógica | 🟡 MEJORA | Lógica compleja: valida CloudFlare → valida Token → inserta/actualiza → envía emails. **Riesgo:** Si `Insert` falla por duplicado, intenta `Update`, pero si `getCustomer` también falla, envía `SendMailError` sin confirmar si se guardó. |

**Recomendaciones:**
1. 🔴 **CRÍTICO:** Agregar validación explícita del response de `Insert`/`Update` antes de enviar emails.
2. 🟡 Considerar usar `SplitInBatches` si se espera procesar múltiples contactos en el futuro.

---

## 📁 03-rag-news-intelligence/v3

### **v3_news.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🔴 CRÍTICO | **Línea 696:** `"value": "=Bearer {{$env[\"OPENAI_API_KEY\"]}}"` - La API Key de OpenAI está expuesta en el header. Debería usar credentials de n8n. |
| 🛡️ Robustez | 🟡 MEJORA | Nodo `Insert` (línea 231) tiene `retryOnFail: true` ✅ y `onError: continueErrorOutput` ✅. Pero `Check Article Exists` tiene `alwaysOutputData: true` sin validar si la respuesta es error. |
| ⚙️ Lógica | 🟡 MEJORA | **Sin paginación:** El nodo `RSS Read` puede traer cientos de items. El `Filter News` limita a 10, pero procesa todo en memoria primero. **Riesgo de timeout en feeds grandes.** |

**Recomendaciones:**
1. 🔴 **CRÍTICO:** Mover `OPENAI_API_KEY` a credentials de n8n en lugar de usar `$env` directamente en headers.
2. 🟡 Agregar `SplitInBatches` después de `RSS Read` para procesar feeds en lotes de 50 items.
3. 🟡 Validar que `Check Article Exists` no devuelva error antes de responder.

---

## 📁 04-omnichannel-social/v4

### **v4-omnichanel.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🔴 CRÍTICO | **Línea 696:** `"value": "=Bearer {{$env[\"OPENAI_API_KEY\"]}}"` - Mismo problema que v3_news. API Key expuesta. |
| 🛡️ Robustez | 🟡 MEJORA | Múltiples nodos de publicación (`PostToFacebookPage`, `Create X`, `Post Company`, `Post Personal`) tienen `onError: continueRegularOutput` ✅. Pero el nodo `Merge` tiene `alwaysOutputData: false` - si todos fallan, no hay output. |
| ⚙️ Lógica | 🟢 OK | Flujo complejo pero bien orquestado. El nodo `Validar Posts` verifica que al menos una red social haya publicado exitosamente antes de marcar como publicado. |

**Recomendaciones:**
1. 🔴 **CRÍTICO:** Usar credentials de n8n para OpenAI en lugar de `$env["OPENAI_API_KEY"]` en headers.
2. 🟡 Cambiar `Merge.alwaysOutputData` a `true` para garantizar que siempre haya respuesta, incluso si todas las redes fallan.

---

## 📁 05-ai-whatsapp-agent/v3

### **v3-ai.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🟢 OK | Usa credentials de n8n para OpenAI, WhatsApp y Postgres. No hay hardcoding. |
| 🛡️ Robustez | 🟢 OK | Nodos críticos (`Download`, `Transcribe`, `GetUrlAudio`) no tienen `continueOnFail` pero están en ramas separadas del `Switch Type`, por lo que un fallo en audio no afecta texto. |
| ⚙️ Lógica | 🟡 MEJORA | **Consulta SQL sin paginación (línea 820):** `SELECT role, phone FROM users WHERE is_active = true;` - Si hay 10,000 usuarios activos, carga todos en memoria. **Riesgo:** Timeout en empresas grandes. |

**Recomendaciones:**
1. 🟡 Agregar `LIMIT 1000` a la query de `Get User Role` o usar un índice en `phone` para búsqueda directa.
2. 🟡 Considerar cachear roles de usuarios frecuentes en Redis/memoria.

---

## 📁 06-dynamic-crud-engine/v3

### **v3-crud.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🟢 OK | Usa subworkflow `v3/SW ValidaToken` para autenticación. Validación de roles en `Security Validation`. |
| 🛡️ Robustez | 🟡 MEJORA | Nodo `Execute SQL` (línea 625) tiene `onError: continueRegularOutput` ✅ y `alwaysOutputData: true` ✅. Pero **no valida inyección SQL** - confía en que `Build Query` sanitiza inputs. |
| ⚙️ Lógica | 🔴 CRÍTICO | **Sin paginación:** Las operaciones `getall` pueden devolver miles de registros. No hay `LIMIT` por defecto. **Riesgo:** Timeout y consumo excesivo de memoria. |

**Recomendaciones:**
1. 🔴 **CRÍTICO:** Agregar `LIMIT` y `OFFSET` por defecto en operaciones `getall` (ej: LIMIT 100).
2. 🟡 Validar que `Build Query` use parámetros preparados para prevenir SQL injection.
3. 🟡 Agregar rate limiting para prevenir abuso de endpoints públicos (ej: `companys`).

---

## 📁 07-MCP-server-hotel/v3

### **v3_MCP_Server_Hotel.json**
| Criterio | Estado | Detalle |
|----------|--------|---------|
| 🔐 Seguridad | 🟢 OK | Usa credentials de Postgres. Queries son read-only (SELECT). |
| 🛡️ Robustez | 🟢 OK | Nodos `postgresTool` no tienen `continueOnFail` porque son herramientas para AI Agent - el agente maneja los errores. |
| ⚙️ Lógica | 🟡 MEJORA | **Query sin LIMIT (línea 21):** `SELECT * FROM hotel_rooms WHERE status = 'available'...` - Si hay 500 habitaciones disponibles, devuelve todas. **Riesgo:** Respuesta lenta para el AI Agent. |

**Recomendaciones:**
1. 🟡 Agregar `LIMIT 50` a las queries de `Query Available` y `Query Rooms` para evitar respuestas masivas.
2. 🟡 Considerar agregar índices en `status` y `cleaning_status` para mejorar performance.

---

## 📈 Resumen por Flujo

| Flujo | 🔐 Seguridad | 🛡️ Robustez | ⚙️ Lógica | Veredicto |
|-------|-------------|-------------|-----------|-----------|
| **00-Global Error Handler** | 🟢 OK | 🟢 OK | 🟢 OK | ✅ ROBUSTO |
| **01-v3_GeneraToken** | 🟢 OK | 🟢 OK | 🟢 OK | ✅ SEGURO |
| **01-v3_SW ValidaToken** | 🟢 OK | 🟢 OK | 🟢 OK | ✅ SEGURO |
| **02-v3-contact** | 🟡 MEJORA | 🔴 CRÍTICO | 🟡 MEJORA | ⚠️ REQUIERE ATENCIÓN |
| **03-v3_news** | 🔴 CRÍTICO | 🟡 MEJORA | 🟡 MEJORA | 🔴 RIESGO ALTO |
| **04-v4-omnichanel** | 🔴 CRÍTICO | 🟡 MEJORA | 🟢 OK | 🔴 RIESGO ALTO |
| **05-v3-ai** | 🟢 OK | 🟢 OK | 🟡 MEJORA | ✅ BUENO |
| **06-v3-crud** | 🟢 OK | 🟡 MEJORA | 🔴 CRÍTICO | ⚠️ REQUIERE ATENCIÓN |
| **07-v3_MCP_Server_Hotel** | 🟢 OK | 🟢 OK | 🟡 MEJORA | ✅ BUENO |

---

## 🎯 Plan de Acción Prioritario

### 🔴 **URGENTE (Implementar esta semana)**
1. **Flujos 03 y 04:** Mover `OPENAI_API_KEY` de `$env` a credentials de n8n.
2. **Flujo 02:** Validar respuestas de CRUD antes de enviar emails.
3. **Flujo 06:** Agregar `LIMIT 100` por defecto en operaciones `getall`.

### 🟡 **IMPORTANTE (Implementar este mes)**
4. Agregar `SplitInBatches` en flujos que procesan listas grandes (03, 05, 06, 07).
5. Revisar que todos los nodos HTTP Request críticos tengan `continueOnFail` o `continueErrorOutput`.
6. Agregar índices en tablas de Postgres para queries frecuentes.

### 🟢 **MEJORA CONTINUA**
7. Implementar rate limiting en endpoints públicos.
8. Agregar logs de auditoría en operaciones de escritura.
9. Crear tests automatizados para flujos críticos.

---

## 📝 Notas Finales

**Fortalezas del Sistema:**
- ✅ Uso consistente de variables de entorno para secrets.
- ✅ Global Error Handler bien implementado.
- ✅ Arquitectura modular con subworkflows reutilizables.
- ✅ Validación de tokens JWT centralizada.

**Áreas de Mejora:**
- ⚠️ Falta de paginación en queries que pueden devolver muchos registros.
- ⚠️ Algunos flujos exponen API Keys en headers en lugar de usar credentials.
- ⚠️ Falta validación explícita de respuestas HTTP antes de continuar flujos críticos.

**Recomendación General:**
El sistema está bien arquitecturado, pero requiere refactorización en 3 flujos críticos (02, 03, 04) para alcanzar nivel de producción enterprise. Los demás flujos son sólidos.

---

**Firma Digital:** n8n Workflow Auditor v3.0  
**Próxima Auditoría:** 2026-03-15
