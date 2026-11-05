# Contexto 098: repasto con retorno

Rol de Claude: arquitecto empresarial senior y PMO técnico. Responde en español; código, nombres y commits en inglés (Conventional Commits con alcance).
Reglas fijas: nunca comandos destructivos contra producción; dry run por defecto; BEGIN, verificación y COMMIT (nunca un COMMIT suelto); borrado lógico; multi-tenant fail-closed por id_company; sin secretos ni datos reales en el chat; no mergear a main (despliega frontends solos).
Producción: Postgres 15.4 en un contenedor del VPS (n8n-enterprise-db, base hosting3m_db). Ensayos en PG16 local con un esquema sin datos.

## Hecho (migración 098, rama feat/agro-erp-grazing-loans-098, 3 commits subidos)
- cattle_movement_events: purpose (REPASTO), expected_return_date.
- cattle_movement_event_animals: return_status (NULL sin seguimiento, OPEN, RETURNED, CANCELLED, DIED_AWAY) y returned_at; índice único parcial: un OPEN por animal. El estado del evento se calcula en vw_livestock_out_on_loan (OPEN, RETURNED, CLOSED).
- Triggers: P0098 impide VENDIDO, FINALIZADO y BAJA_DEPURACION_DATOS con renglón OPEN; la muerte cierra como DIED_AWAY; P0100 impide abrir préstamo de animal terminal o fuera de la UPP de origen.
- sp_return_movement (P0099): ADMIN/OWNER, retorno parcial e idempotente; el correo del actor sale de la sesión verificada, nunca de $fromAI.
- sp_solicitar_venta_orden se parchea desde su definición viva por 4 anclas de texto (rechazo "Animal fuera en repasto..." y exclusión en FIFO). El rollback la devuelve byte a byte.
- 83 aserciones, 6 mutaciones detectadas, concurrencia probada en ambos órdenes.
- Seed del prototipo solo en la empresa 3: 31 animales con arete ficticio '99'||right(real,8), 3 guías (7139728, 7139729, PRUEBA-3A-GUIA), destino Moisés Guichard (UPP 07-068-0171-001). business_model='CRIA' sin confirmar con el dueño.

## Pendiente, en orden
1. Dry run de 098 en producción (comprueba las anclas en PG 15.4), con "adelante" explícito. Luego respaldo, state_check before, apply, state_check applied y el paso 5b de crud_models.
2. Seed en la empresa 3 y verificación por el canal real de que el agente relata "Animal fuera en repasto...". (En el runbook, el seed es el paso 6 y la prueba funcional el 7, que usa animales del seed.)
3. Confirmar business_model con Alejandro.
4. Deuda: sp_move_livestock y cambios de UPP/lote con renglón OPEN no están bloqueados.
5. Fuera de alcance: carga real de los 31 (rfid_siniiga es UNIQUE global; Santa Lucía, empresa 8, BLOQUEADA y por levantarse; Maceo es un lote de San José y La Pita, empresa 5) y la aparcería (16 novillonas, sin respuestas a las 19 preguntas).
