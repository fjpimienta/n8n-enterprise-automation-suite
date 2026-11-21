import { DIFFERENTIATORS } from './content';
import { cfdiClaim } from './cfdi-claim';

describe('CFDI claim card', () => {
  it('is not part of the differentiators while the flag is off', () => {
    expect(DIFFERENTIATORS.map((d) => d.title)).toEqual(['Atención local en Mérida', 'En español', 'Automatización administrada']);
    expect(JSON.stringify(DIFFERENTIATORS)).not.toMatch(/TODO_|CFDI/);
  });

  it('keeps its pending copy ready behind the flag, still as TODO_ tokens', () => {
    expect(cfdiClaim()).toEqual({ title: 'TODO_CFDI_CLAIM_TITLE', text: 'TODO_CFDI_CLAIM_TEXT' });
  });
});
