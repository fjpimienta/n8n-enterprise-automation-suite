import { shouldClearStoredPlantations } from './plantation-clear.util';

describe('shouldClearStoredPlantations', () => {
  it('keeps stored choices on a cold start in grace', () => {
    expect(shouldClearStoredPlantations(false, 'grace')).toBe(false);
  });

  it('clears when there is no session at all', () => {
    expect(shouldClearStoredPlantations(false, 'expired')).toBe(true);
    expect(shouldClearStoredPlantations(false, 'valid')).toBe(true);
  });

  it('keeps them while authenticated', () => {
    expect(shouldClearStoredPlantations(true, 'valid')).toBe(false);
  });
});
