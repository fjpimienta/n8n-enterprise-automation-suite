import { COOKIES } from './cookies';
import { PRIVACY } from './privacy';
import { TERMS } from './terms';
import type { LegalDoc } from './types';

export const LEGAL_DOCS: Readonly<Record<LegalDoc['slug'], LegalDoc>> = { privacy: PRIVACY, cookies: COOKIES, terms: TERMS };
export type { LegalBlock, LegalDoc, LegalSection } from './types';
