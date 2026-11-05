# Contexto 098: repasto con retorno

Rol de Claude: arquitecto empresarial senior y PMO técnico. Responde en español; código, nombres y commits en inglés (Conventional Commits con alcance).
Reglas fijas: nunca comandos destructivos contra producción; dry run por defecto; BEGIN, verificación y COMMIT (nunca un COMMIT suelto); borrado lógico; multi-tenant fail-closed por id_company; sin secretos ni datos reales en el chat; no mergear a main (despliega frontends solos).
Producción: Postgres 15.4 en un contenedor del VPS (n8n-enterprise-db, base hosting3m_db). Ensayos en PG16 local con un esquema sin datos.
Hábito: git push después de cada commit; el contexto vive en el repo, no en los chats.

## Estado: DESPLEGADA EN PRODUCCIÓN el 2026-11-05
Migración 098, rama feat/agro-erp-grazing-loans-098 (PR a develop; no mergear a main hasta decidirlo).
- Dry run con las 4 anclas OK en PG 15.4 (md5 vivo de sp_solicitar_venta_orden 30e1b66c...; después 94d45947...).
- Respaldo previo: hosting3m_pre098_2026-11-05_0955.dump (en /root del VPS).
- state_check before y applied OK; huellas de datos idénticas; sal5/sal4/sal1/baja sin cambios.
- Paso 5b crud_models: se quitó UPDATE al modelo cattle_movement_event_animals (ahora SELECT, INSERT, GETONE, GETALL). Los cierres solo por sp_return_movement.
- Seed del prototipo aplicado en la empresa 3: 31 animales, 3 movimientos, 31 renglones OPEN.
- P0098 probado en producción (UPDATE a VENDIDO falla) y verificado por el canal real: el agente relata "fuera en repasto, guía 7139728, retorno 2026-12-14".

## Qué hace la 098
- cattle_movement_events: purpose (REPASTO), expected_return_date.
- cattle_movement_event_animals: return_status (NULL sin seguimiento, OPEN, RETURNED, CANCELLED, DIED_AWAY) y returned_at; índice único parcial: un OPEN por animal. El estado del evento se calcula en vw_livestock_out_on_loan (OPEN, RETURNED, CLOSED).
- Triggers: P0098 impide VENDIDO, FINALIZADO y BAJA_DEPURACION_DATOS con renglón OPEN; la muerte cierra como DIED_AWAY; P0100 impide abrir préstamo de animal terminal o fuera de la UPP de origen.
- sp_return_movement (P0099): ADMIN/OWNER, retorno parcial e idempotente; el correo del actor sale de la sesión verificada, nunca de $fromAI.
- sp_solicitar_venta_orden se parchea desde su definición viva por 4 anclas de texto (rechazo "Animal fuera en repasto..." y exclusión en FIFO). El rollback la devuelve byte a byte.
- 83 aserciones, 6 mutaciones detectadas, concurrencia probada en ambos órdenes (PG16 local).
- Prototipo solo en la empresa 3: 31 animales con arete ficticio '99'||right(real,8), 3 guías (7139728, 7139729, PRUEBA-3A-GUIA), destino Moisés Guichard (UPP 07-068-0171-001).

## Pendiente, en orden
1. Confirmar business_model con Alejandro (hoy CRIA, sin confirmar). Si cambia: UPDATE revisado, en transacción, solo empresa 3.
2. Abrir/cerrar el PR a develop (recuadro ⛔ en la primera línea; no mergear a main).
3. Deuda: sp_move_livestock y cambios de UPP/lote con renglón OPEN no están bloqueados.
4. Deuda: cattle_movement_events permite editar expected_return_date sin auditoría (modelo crud_models con UPDATE ADMIN,OWNER).
5. Mejoras menores del agente: pregunta de más antes de la vista previa; para bovinos sin guía sale "Falta la guía" antes que el motivo de repasto.
6. Limpieza: borrar .sql de /root en el VPS (dejar respaldo y 098_*.txt unos días); shred de ~/.pgpass y ~/.pg_098_env en el equipo de ensayo; revocar la llave SSH del equipo perdido en GitHub.
7. Fuera de alcance: carga real de los 31 (rfid_siniiga es UNIQUE global; Santa Lucía, empresa 8, BLOQUEADA y por levantarse; Maceo es un lote de San José y La Pita, empresa 5) y la aparcería (16 novillonas, sin respuestas a las 19 preguntas).
