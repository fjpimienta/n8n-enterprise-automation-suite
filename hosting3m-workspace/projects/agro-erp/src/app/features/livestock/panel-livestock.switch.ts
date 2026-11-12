/**
 * Code-constant switch for the panel livestock ALTA flow (preview -> confirm through
 * `registerLivestockPanel`). OFF keeps the legacy `altaForm` + `createLivestock` flow exactly as
 * it was. Turning it ON is a one-line PR (PR 5); removing the legacy flow is PR 6.
 *
 * Deliberately NOT in `src/environments/`: rollback is reverting a one-line change.
 */
export const PANEL_LIVESTOCK_ALTA_ENABLED = false;
