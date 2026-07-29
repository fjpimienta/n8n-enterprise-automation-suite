# Inventario de completitud — Agro ERP / Padrón Aguilar Reséndez

**Corte:** 29 de julio de 2026 · Producción (`hosting3m_db`)
**Alcance:** 270 animales activos, 4 unidades de producción, 2 titulares, 2 fierros

---

## Resumen ejecutivo

| Bloque | Estado | Bloquea |
|---|---|---|
| Registro de UPP | 4 de 5 cargadas | Trazabilidad completa |
| Identificación animal | 245/270 con arete válido | Movilización legal |
| Identidad electrónica | **8/270 con bolo** | Todo el flujo de salida |
| Propiedad (fierro) | **0/270 asignados** | Reportes por fierro |
| Sanidad | **0 dictámenes de hato libre** | Movilización (5/270 movilizables) |
| Expediente documental | **0 archivos** | Auditoría |
| Inventario real UPP 54 | 54 en sistema vs +130 en papel | Confiabilidad del hato |

---

## 1. Crítico — impide operar

### 1.1 Bolo ruminal ausente en el 97% del hato

| Empresa | Animales | Sin `electronic_rfid` |
|---|---|---|
| La Bendición | 216 | **208 (96%)** |
| UPP 54 | 54 | **54 (100%)** |

**Por qué importa.** `ARCHITECTURE.md` y `CLAUDE.md` declaran `electronic_rfid` como *Primary Operational Key* y ordenan priorizarlo sobre el arete. Pero `sp_procesar_salida_ganado` se invoca **por `electronic_rfid`**: hoy solo 8 animales pueden procesarse por el flujo oficial de salida. Los otros 262 no tienen forma de entrar al procedimiento.

**Decisión de negocio pendiente (cliente):** ¿se van a colocar bolos al hato completo, o el arete SINIIGA pasa a ser la llave operativa? De la respuesta depende si hay que agregar una sobrecarga del SP que acepte `rfid_siniiga`.

**Riesgo si no se resuelve:** el módulo de salida es inutilizable en producción.

### 1.2 Sin dictamen de hato libre — solo 5 de 270 movilizables

`herd_free_certificates` está vacía en las 4 UPP, y las pruebas TB/BR individuales están mayormente sin registrar. Bajo la NOM-031 y NOM-041, sin uno de los dos ningún animal puede movilizarse.

**Pendiente (cliente):** ¿cuenta con dictamen vigente de hato libre de TB y Brucelosis? Si lo tiene y no lo hemos cargado, este indicador cambia por completo.

**Riesgo:** el tablero de movilidad muestra un dato alarmante que puede ser artefacto nuestro.

### 1.3 Fierro sin asignar en los 270 animales

El cliente pidió explícitamente reportes financieros separados por fierro. La estructura existe (`brand_registrations`, `cattle_livestock.brand_id`, herencia materna automática), pero **ningún animal tiene fierro asignado**, así que `vw_livestock_by_brand` sale vacía.

**No es automatizable.** El fierro está marcado en el animal y anotado en las libretas; no hay campo en la base del que inferirlo.

**Vía de solución:** el recorrido de inventario físico. Si la hoja impresa lleva casilla para anotar el fierro observado, un solo recorrido resuelve conteo y propiedad.

---

## 2. Alto — compromete la integridad del dato

### 2.1 UPP 54: el inventario del sistema no corresponde al real

| Fuente | Contenido |
|---|---|
| Sistema | 54 búfalos |
| Constancia F-887211 | 102 bovinos + 9 equinos |
| Libretas | +130 bovinos, 27 borregos, 8 caballos, búfalos con peso |

**Pendiente (cliente):** confirmar el inventario real. Es probable que el sistema tenga cargada solo una fracción.

### 2.2 Número a fuego ausente en UPP 54

| Empresa | Sin `numero_fuego` |
|---|---|
| La Bendición | 0 de 216 |
| UPP 54 | **54 de 54** |

Son dos prácticas de manejo distintas: La Bendición marca a fuego, UPP 54 solo aretea. **Consecuencia práctica:** la hoja de inventario que pidió el cliente no puede ordenarse por fuego en UPP 54; ahí debe ir por arete. La plantilla tiene que adaptarse por unidad.

### 2.3 Linaje materno sin registrar

`mother_id` está en NULL en los 270. Las libretas registran cada parto con el arete y el quemado de la madre desde 2023, y el Excel PARTOS_2020 tiene 417 partos más. Es la fuente para poblarlo.

Sin linaje, la herencia automática del fierro no puede operar sobre el hato existente.

### 2.4 Cuatro aretes irrecuperables

| Arete | Fuego | Nota |
|---|---|---|
| `72892636` | 1688 | 8 dígitos, falta(n) dígito(s) intermedio(s) |
| `71396744` | 1810 | 8 dígitos |
| `12654656` | `20199-84` | el fuego también es anómalo (9 caracteres) |
| `09-1234` | 1234 | parece el fuego capturado en el campo del arete |

Cuatro vacas de La Bendición. Se ubican por número a fuego y se lee el arete físico.

*(Los 188 aretes de 9 dígitos ya fueron corregidos: habían perdido el cero inicial del prefijo 07 en un import.)*

### 2.5 Veintiún animales sin arete oficial

Registrados como `S/N-<fuego>-<n>`, que corresponde al `S/A` (sin arete) de las libretas. **Está bien capturado**: refleja la realidad.

**Regla del cliente:** *"al momento que nos den la reposición de aretes se determinará en qué UPP queda ubicada y se ligará al quemado"*. O sea, aretar es un evento con consecuencia registral que hay que modelar.

---

## 3. Medio — requisitos normativos incompletos

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

---

## 4. Modelo — entidades que faltan

| Entidad | Evidencia | Estado |
|---|---|---|
| **Potreros** | "potrero 1/2/3" con fecha en las libretas | No modelado |
| **Evento de parto** | Serie 2023–2026 en libretas + 417 en Excel 2020 | No modelado |
| **Ciclo de vida del arete** | *"Aretes quitados en La Bendición para reponer en San Pedro"* | No modelado |
| **Predios arrendados de terceros** | Navarro Ble, Ing. Alejandro — sin UPP propia | No modelado |
| **Equinos** | 8 caballos con desglose (yeguas, potro, castrados) | CHECK de especie no los admite — **verificar** |
| **Borregos** | 27 cabezas en UPP 54 | `category` sí los admite |
| **Estado reproductivo detallado** | "Parida: hembra 4 meses", "Preñada 02 meses", "Vacía siciando" | Solo `PREÑADA`/`VACÍA` |
| **Terceros sin rol claro** | "Pedro y Claudia", "Novillonas Gerardo" | Pendiente de aclarar |

---

## 5. Deuda técnica heredada

Documentada en `DOCS_DELTA_v1.9.0_FINAL.md` (DT-01 a DT-12). Las dos que más pesan:

- **DT-09** — `n8n_user` es superusuario. Toda la seguridad depende de la whitelist de `crud_models`, sin segunda línea de defensa en base de datos.
- **DT-06** — `execute_metacrud_write` es incompatible con PK UUID (`p_record_id integer`), lo que afecta a todas las tablas `cattle_*`.

---

## 6. Secuencia recomendada

**Ahora, sin depender del cliente**
1. Ampliar el catálogo de especies para equinos (verificar primero el CHECK actual)
2. Modelar potreros y evento de parto — estructura, sin datos
3. Hoja de inventario impresa **con casilla de fierro**: un recorrido resuelve conteo, propiedad y verificación de aretes

**Al recibir respuesta del cliente**
4. Alta de la UPP 6515 y credencial del fierro `aR`
5. Carga del dictamen de hato libre → recalcula el indicador de movilidad
6. Decisión sobre el bolo ruminal → define la llave operativa del SP de salida
7. Reconciliación del inventario de UPP 54

**Al completar el recorrido de campo**
8. Asignación masiva de `brand_id`
9. Corrección de los 4 aretes anómalos
10. Digitalización de libretas → linaje materno y serie histórica

---

## Anexo — verificación

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
