import { isPinFormat, isTrivialPin } from './pin-policy.util';

describe('pin-policy', () => {
  it('accepts exactly six ASCII digits', () => {
    expect(isPinFormat('482915')).toBe(true);
    for (const bad of ['12345', '1234567', '12a456', ' 12345', '١٢٣٤٥٦', 123456 as unknown as string]) {
      expect(isPinFormat(bad)).toBe(false);
    }
  });

  it('flags repeated, ascending and descending PINs as trivial', () => {
    for (const t of ['000000', '777777', '123456', '012345', '654321', '987654']) {
      expect(isTrivialPin(t)).toBe(true);
    }
    for (const ok of ['482915', '123465', '112233', '135791']) {
      expect(isTrivialPin(ok)).toBe(false);
    }
  });
});
