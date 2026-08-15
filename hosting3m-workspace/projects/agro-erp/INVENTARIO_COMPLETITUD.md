# Inventario de completitud — Agro ERP / Padrón Aguilar Reséndez

## Actualización desde el corte anterior (2026-07-29 → 2026-08-14)

### Cerrado desde el corte anterior

- **Reglas de movimiento UPP↔PSG** (antes en "Deuda técnica activa" como sin definir):
  dejaron de estar en borrador. 16 filas confirmadas contra reglas de negocio reales del
  cliente; enforcement real sigue inactivo pendiente de un solo dato (ver abajo).
- **`herd_free_certificates` registrada en `crud_models`** — existía desde migración 024,
  nunca expuesta vía Meta-CRUD hasta ahora.
- **Rotación de `INTERNAL_SECRET` confirmada** (2026-08-15) — ver detalle en "Cerrado desde
  el 2026-08-14" más abajo.
- **`jwt-service`: `/verify-token` ahora valida `internal_secret`** — también reveló y
  corrigió un bug de "fail open" no relacionado, y una segunda rotación de secreto pendiente
  que la primera confirmación había dejado incompleta. Ver detalle abajo.
- Ver `ARCHITECTURE.md` y `DATABASE_SCHEMA.md` (docs/) para el detalle técnico completo.

### Crítico, bloquea operación

*(Sin ítems activos al corte 2026-08-15 — el único ítem crítico, la rotación de
`INTERNAL_SECRET`, se confirmó cerrado. Ver histórico abajo.)*

### Alto, requiere respuesta del cliente

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

### Medio, sin bloquear nada hoy

#### Ambigüedad `requires_valid_psg` vs. `requires_health_tests` — documentada, no verificada independientemente

Se aclaró por escrito (migración 048) que son dos conceptos distintos (licencia del PSG vs.
estatus sanitario del animal), pero en la matriz confirmada de 042 ambas se fijaron con los
mismos valores bajo el supuesto de que coincidían. No se ha verificado contra un documento
real si de hecho coinciden siempre o si hay un caso donde divergen.

#### `schema.sql` desactualizado (de nuevo)

Verificado 2026-08-14: cero coincidencias en el `schema.sql` versionado para cualquier
objeto de las migraciones 042-049. Regenerar con `pg_dump --schema-only` contra producción
antes de usarlo como fuente de diagnóstico — tercera vez que este archivo se desactualiza
respecto a producción (ver `CLAUDE.md`, regla 7, para las dos anteriores).

#### `cattle_movement_events` editable, no append-only

Decisión del cliente (no un descuido): la bitácora de movimientos permite `UPDATE` en vez de
un patrón de corrección append-only, pese a que un folio REEMO es un registro de
cumplimiento. Documentado como candidato a revisar si surge una necesidad real de corrección
posterior a la captura — no se ha revisitado desde entonces.

#### Numeración de módulos inconsistente en el `README.md` de la suite (raíz del monorepo)

La lista de prosa de módulos y la tabla de documentación técnica traían números distintos
para los mismos servicios (Core Auth como 14 en un lado, 15 en el otro; MCP Field Agent
ausente de la prosa). Corregido 2026-08-15 alineando la prosa a la tabla — sin acción
pendiente, se deja anotado por si el mismo tipo de desalineación vuelve a aparecer al
agregar módulos futuros.

#### Esquema de versionado entre `CHANGELOG.md` (suite) y versión interna de `agro-erp`

Ambos esquemas comparten números por coincidencia, no por diseño (`v1.7.0` de la suite no es
lo mismo que `v1.7.0` de `agro-erp`). Recomendación en discusión al corte de este documento:
mover el `CHANGELOG.md` de la suite a versionado por fecha (CalVer, ej. `[2026-08-14]`) para
eliminar la ambigüedad de raíz en vez de solo documentarla.

---

## Cerrado desde el 2026-08-14

### `INTERNAL_SECRET` expuesto durante el trabajo de endurecimiento de `upload-file` — ROTADO

El valor real del secreto compartido entre `n8n-jwt-service` y `upload-file` se pegó en
texto plano en una sesión de trabajo (dos veces), incluyendo en el servidor de producción.
**Rotación confirmada completada el 2026-08-15** en ambos servicios y ambos ambientes
(espejo local y VPS de producción). Ver el hallazgo relacionado justo debajo — la primera
confirmación de rotación resultó incompleta.

`upload-file/server.js` recibió además una segunda ronda de endurecimiento el 2026-08-15,
independiente del incidente de exposición: rate limiting (100 peticiones/15 min por IP),
sanitización de extensión de archivo subido, y protección explícita contra path traversal
(hallazgo de análisis estático CodeQL) en la ruta de lectura de archivo tras la subida.
**Desplegado y verificado en local y producción el 2026-08-15** — requirió un segundo
intento en producción por corrupción del archivo al transferirlo vía base64 en una sola
línea (la terminal partía la línea larga de forma consistente); resuelto usando un heredoc
con el contenido real del archivo en vez de base64 de una sola línea.

### `jwt-service` — `/verify-token` no validaba `internal_secret` — CERRADO

El pendiente original: el nodo n8n `Verify Token` mandaba el header `internal_secret`, pero
el endpoint nunca lo validaba (solo `/generate-token` lo revisaba). Al corregirlo aparecieron
dos hallazgos más serios que el original, cerrados en el mismo cambio:

- **Bug de "fail open" real, sin explotar hasta donde se sabe.** `/generate-token` compara
  `internal_secret !== INTERNAL_SECRET` sin verificar antes que `INTERNAL_SECRET` esté
  configurado. Si la variable de entorno faltara, `undefined !== undefined` es `false` — la
  validación pasaría en silencio para cualquier llamador que simplemente no mande
  `internal_secret`. Se agregó el mismo chequeo de arranque fail-closed que ya tenía
  `upload-file` (`JWT_SECRET`/`INTERNAL_SECRET` ausentes → el proceso se niega a arrancar).
- **La rotación de `INTERNAL_SECRET` confirmada el 2026-08-15 (arriba) resultó incompleta.**
  Al verificar el fix en el espejo local, se descubrió que `infrastructure/.env.local`
  seguía con el valor ya marcado como comprometido — la confirmación anterior solo había
  cubierto producción. Rotado correctamente esta vez en ambos servicios y ambos ambientes,
  verificado con una prueba funcional que nunca requirió copiar el valor del secreto a
  ningún lado (genera un JWT de prueba y lee los secretos directo de `process.env` dentro
  del propio contenedor).
- Aparte, se corrigió un error real en `.gitignore`: la regla `*.bak-*` agregada durante
  este trabajo se había concatenado sin salto de línea a la regla anterior, reduciendo su
  alcance a solo `infrastructure/n8n_data/executions/*.bak-*` en vez de aplicar a todo el
  repo — un archivo `.bak` de esta misma sesión estuvo a punto de subirse por accidente.

### `n8n` como tercer consumidor de `INTERNAL_SECRET` — hallazgo posterior a la rotación

Tras rotar `INTERNAL_SECRET` en `jwt-service` y `upload-file` (arriba), el login del frontend
empezó a fallar con `401`/`403` en `v4/genera-token`. Causa: **el propio contenedor de `n8n`
también lee `INTERNAL_SECRET`** desde el mismo `infrastructure/.env` (vía `$env[...]` dentro
del workflow `GenerateToken`), pero nunca se reinició durante la rotación — deliberadamente
se evitó tocarlo para no repetir el error `429` de Docker Hub al reconstruirlo. Un contenedor
no relee su `.env` solo; necesita reiniciarse (no reconstruirse) para tomar un valor nuevo.
Resuelto con `docker compose up -d n8n` (sin `--build`, usa la imagen ya en caché, sin
descargar nada) y confirmado con el login real desde el navegador.

**Lección para la próxima rotación de cualquier secreto compartido:** identificar primero
*todos* los consumidores reales antes de rotar, no asumir que son solo los servicios cuyo
código se tocó en la sesión. `INTERNAL_SECRET` termina teniendo 3 consumidores
(`jwt-service`, `upload-file`, `n8n`), no 2.

---

## Inventario original — corte 2026-07-29

**Alcance:** 270 animales activos, 4 unidades de producción, 2 titulares, 2 fierros

### Resumen ejecutivo

| Bloque | Estado | Bloquea |
|---|---|---|
| Registro de UPP | 4 de 5 cargadas | Trazabilidad completa |
| Identificación animal | 245/270 con arete válido | Movilización legal |
| Identidad electrónica | **8/270 con bolo** | Todo el flujo de salida |
| Propiedad (fierro) | **0/270 asignados** | Reportes por fierro |
| Sanidad | **0 dictámenes de hato libre** | Movilización (5/270 movilizables) |
| Expediente documental | **0 archivos** | Auditoría |
| Inventario real UPP 54 | 54 en sistema vs +130 en papel | Confiabilidad del hato |

### 1. Crítico — impide operar

#### 1.1 Bolo ruminal ausente en el 97% del hato

| Empresa | Animales | Sin `electronic_rfid` |
|---|---|---|
| La Bendición | 216 | **208 (96%)** |
| UPP 54 | 54 | **54 (100%)** |

**Por qué importa.** `ARCHITECTURE.md` y `CLAUDE.md` declaran `electronic_rfid` como *Primary Operational Key* y ordenan priorizarlo sobre el arete. Pero `sp_procesar_salida_ganado` se invoca **por `electronic_rfid`**: hoy solo 8 animales pueden procesarse por el flujo oficial de salida. Los otros 262 no tienen forma de entrar al procedimiento.

**Decisión de negocio pendiente (cliente):** ¿se van a colocar bolos al hato completo, o el arete SINIIGA pasa a ser la llave operativa? De la respuesta depende si hay que agregar una sobrecarga del SP que acepte `rfid_siniiga`.

**Riesgo si no se resuelve:** el módulo de salida es inutilizable en producción.

#### 1.2 Sin dictamen de hato libre — solo 5 de 270 movilizables

`herd_free_certificates` está vacía en las 4 UPP, y las pruebas TB/BR individuales están mayormente sin registrar. Bajo la NOM-031 y NOM-041, sin uno de los dos ningún animal puede movilizarse.

**Pendiente (cliente):** ¿cuenta con dictamen vigente de hato libre de TB y Brucelosis? Si lo tiene y no lo hemos cargado, este indicador cambia por completo.

**Riesgo:** el tablero de movilidad muestra un dato alarmante que puede ser artefacto nuestro.

#### 1.3 Fierro sin asignar en los 270 animales

El cliente pidió explícitamente reportes financieros separados por fierro. La estructura existe (`brand_registrations`, `cattle_livestock.brand_id`, herencia materna automática), pero **ningún animal tiene fierro asignado**, así que `vw_livestock_by_brand` sale vacía.

**No es automatizable.** El fierro está marcado en el animal y anotado en las libretas; no hay campo en la base del que inferirlo.

**Vía de solución:** el recorrido de inventario físico. Si la hoja impresa lleva casilla para anotar el fierro observado, un solo recorrido resuelve conteo y propiedad.

### 2. Alto — compromete la integridad del dato

#### 2.1 UPP 54: el inventario del sistema no corresponde al real

| Fuente | Contenido |
|---|---|
| Sistema | 54 búfalos |
| Constancia F-887211 | 102 bovinos + 9 equinos |
| Libretas | +130 bovinos, 27 borregos, 8 caballos, búfalos con peso |

**Pendiente (cliente):** confirmar el inventario real. Es probable que el sistema tenga cargada solo una fracción.

#### 2.2 Número a fuego ausente en UPP 54

| Empresa | Sin `numero_fuego` |
|---|---|
| La Bendición | 0 de 216 |
| UPP 54 | **54 de 54** |

Son dos prácticas de manejo distintas: La Bendición marca a fuego, UPP 54 solo aretea. **Consecuencia práctica:** la hoja de inventario que pidió el cliente no puede ordenarse por fuego en UPP 54; ahí debe ir por arete. La plantilla tiene que adaptarse por unidad.

#### 2.3 Linaje materno sin registrar

`mother_id` está en NULL en los 270. Las libretas registran cada parto con el arete y el quemado de la madre desde 2023, y el Excel PARTOS_2020 tiene 417 partos más. Es la fuente para poblarlo.

Sin linaje, la herencia automática del fierro no puede operar sobre el hato existente.

#### 2.4 Cuatro aretes irrecuperables

| Arete | Fuego | Nota |
|---|---|---|
| `72892636` | 1688 | 8 dígitos, falta(n) dígito(s) intermedio(s) |
| `71396744` | 1810 | 8 dígitos |
| `12654656` | `20199-84` | el fuego también es anómalo (9 caracteres) |
| `09-1234` | 1234 | parece el fuego capturado en el campo del arete |

Cuatro vacas de La Bendición. Se ubican por número a fuego y se lee el arete físico.

*(Los 188 aretes de 9 dígitos ya fueron corregidos: habían perdido el cero inicial del prefijo 07 en un import previo.)*

#### 2.5 Veintiún animales sin arete oficial

Registrados como `S/N-<fuego>-<n>`, que corresponde al `S/A` (sin arete) de las libretas. **Está bien capturado**: refleja la realidad.

**Regla del cliente:** *"al momento que nos den la reposición de aretes se determinará en qué UPP queda ubicada y se ligará al quemado"*. O sea, aretar es un evento con consecuencia registral que hay que modelar. *(Nota 2026-08-14: este modelo ya existe — ver `cattle_identifier_history`, migración 047, que registra automáticamente cualquier reasignación de arete/fuego/chip.)*

### 3. Medio — requisitos normativos incompletos

| Faltante | Detalle | Quién lo aporta |
|---|---|---|
| **UPP 07-065-6515-001** | La Bendición de Dios, titular Pedro. No está en el sistema | Cliente (constancia) |
| **Patente de fierro** | Vacía en las 3 UPP de Alejandro. Requisito para guía de tránsito estatal | Cliente |
| **PSG de Puyacatengo** | Pedro es titular y no tiene licencia registrada | Cliente |
| **Credencial fierro `aR`** | Registro estatal, municipal y fechas en NULL | Cliente |
| **Vigencia PSG** | Se asume 12 meses; el de Tabasco sale vencido bajo ese supuesto | Cliente |
| **Documentos archivados** | Cero PDF en `compliance_documents`. Todo sigue en papel | Cliente + captura |
| **Significado de "bloqueada"** | Santa Lucía. ¿Suspensión SENASICA o baja voluntaria? | Cliente |
| **Nombre de la empresa id 5** | El cliente le dice "San José"; la constancia dice "La Bendición de Dios (San José y La Pita)" | Cliente |
| **Predio de Repasto de Pedro** | ¿Es el mismo Puyacatengo con otro trámite, o un predio físico distinto? | **Resuelto 2026-08:** confirmado, es el mismo Puyacatengo. |

### 4. Modelo — entidades que faltan

| Entidad | Evidencia | Estado |
|---|---|---|
| **Potreros** | "potrero 1/2/3" con fecha en las libretas | No modelado |
| **Evento de parto** | Serie 2023–2026 en libretas + 417 en Excel 2020 | Modelado (`birth_events`, migración 030) — carga de datos históricos pendiente |
| **Ciclo de vida del arete** | *"Aretes quitados en La Bendición para reponer en San Pedro"* | **Resuelto 2026-08** — ver `cattle_identifier_history`, migración 047 |
| **Predios arrendados de terceros** | Navarro Ble, Ing. Alejandro — sin UPP propia | Modelado (`leased_land_sites`, migración 031) |
| **Equinos** | 8 caballos con desglose (yeguas, potro, castrados) | Soportado desde migración 029 |
| **Borregos** | 27 cabezas en UPP 54 | `category` sí los admite |
| **Estado reproductivo detallado** | "Parida: hembra 4 meses", "Preñada 02 meses", "Vacía siciando" | Solo `PREÑADA`/`VACÍA` |
| **Terceros sin rol claro** | "Pedro y Claudia", "Novillonas Gerardo" | Pendiente de aclarar |
| **Reglas de movimiento UPP↔PSG** | `cattle_movement_rules` | **Resuelto 2026-08** — confirmado y aplicado, ver sección de arriba |

### 5. Deuda técnica heredada

- **`n8n_user` superusuario** — toda la seguridad depende de la whitelist de `crud_models`, sin segunda línea de defensa en base de datos (RLS inaplicable mientras esto no cambie).
- **`execute_metacrud_write` incompatible con PK UUID** (`p_record_id integer`), lo que afecta a todas las tablas `cattle_*`. No es la ruta real de escritura del gateway (ver `ARCHITECTURE.md`).

### 6. Secuencia recomendada (histórica — mantenida por trazabilidad)

**Ahora, sin depender del cliente**
1. ~~Ampliar el catálogo de especies para equinos~~ — hecho, migración 029.
2. ~~Modelar potreros y evento de parto~~ — hecho, migraciones 030/031.
3. Hoja de inventario impresa **con casilla de fierro**: un recorrido resuelve conteo, propiedad y verificación de aretes — sigue pendiente.

**Al recibir respuesta del cliente**
4. Alta de la UPP 6515 y credencial del fierro `aR`.
5. Carga del dictamen de hato libre → recalcula el indicador de movilidad.
6. Decisión sobre el bolo ruminal → define la llave operativa del SP de salida.
7. Reconciliación del inventario de UPP 54.

**Al completar el recorrido de campo**
8. Asignación masiva de `brand_id`.
9. Corrección de los 4 aretes anómalos.
10. Digitalización de libretas → linaje materno y serie histórica.

### Anexo — verificación

```sql
-- Completitud por empresa
SELECT c.id_company, c.company_name,
       count(cl.id) AS animales,
       count(*) FILTER (WHERE cl.brand_id IS NULL)        AS sin_fierro,
       count(*) FILTER (WHERE cl.numero_fuego IS NULL)    AS sin_fuego,
       count(*) FILTER (WHERE NOT public.fn_has_official_ear_tag(cl.rfid_siniiga)) AS sin_arete,
       count(*) FILTER (WHERE cl.electronic_rfid IS NULL) AS sin_bolo,
       count(*) FILTER (WHERE cl.mother_id IS NULL)       AS sin_madre
  FROM cattle_livestock cl
  LEFT JOIN companys c ON c.id_company = cl.tenant_id
 WHERE cl.current_status NOT IN ('VENDIDO','BAJA_MORTANDAD')
 GROUP BY 1,2 ORDER BY 1;

-- Estado del padrón
SELECT pu.upp_code, pu.ranch_name, pu.registry_status, p.full_name AS titular,
       pu.fire_brand_patent,
       (SELECT count(*) FROM psg_licenses pl WHERE pl.id_company = pu.id_company) AS psg,
       (SELECT count(*) FROM herd_free_certificates h WHERE h.production_unit_id = pu.id) AS hato_libre,
       (SELECT count(*) FROM compliance_documents d WHERE d.entity_id = pu.id) AS docs
  FROM production_units pu
  LEFT JOIN livestock_producers p ON p.id = pu.producer_id
 ORDER BY pu.upp_code;
```