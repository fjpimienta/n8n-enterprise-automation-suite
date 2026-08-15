# Propuesta de adición a CONTRIBUTING.md — Manejo de Secretos

*No es un reemplazo del archivo completo — es una sección para agregar al final del
`CONTRIBUTING.md` existente, si la aprueban. Nace directo del incidente real de
`INTERNAL_SECRET` expuesto en una sesión de trabajo el 2026-08-13 (ver
`agro-erp/CLAUDE.md`, regla 8).*

---

## Manejo de Secretos y Credenciales

- **Nunca compartas valores reales** de tokens, API keys, contraseñas o secretos
  compartidos (`INTERNAL_SECRET`, `JWT_SECRET`, etc.) en Issues, Pull Requests, chats de
  trabajo, o cualquier canal no cifrado — ni siquiera para "confirmar que coincide". Usa
  `****` o confirma con un sí/no en su lugar.
- **Los secretos van en `.env`, nunca en `docker-compose.yml` ni en ningún archivo
  versionado.** Verifica que `.env` esté en `.gitignore` antes de tu primer commit en
  cualquier servicio nuevo.
- Si un secreto se expone por accidente (commit, chat, log), **trátalo como comprometido
  de inmediato** y avisa para rotarlo en todos los servicios y ambientes donde se use —
  no lo dejes como pendiente de baja prioridad.

---

¿Se agrega tal cual al `CONTRIBUTING.md`, se ajusta el tono, o prefieres no tocar ese
archivo por ahora?