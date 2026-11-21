/**
 * Copy of the CFDI claim card. Pending content: the TODO_ tokens must be replaced with an exact, verifiable claim before
 * the flag in `content.ts` (the `false` literal in DIFFERENTIATORS) is switched on. This module is only reachable through
 * that flag, so while it is off the text is dropped from the build output (the production TODO guard then does not see it).
 */
export const cfdiClaim = () => ({ title: 'TODO_CFDI_CLAIM_TITLE', text: 'TODO_CFDI_CLAIM_TEXT' }) as const;
