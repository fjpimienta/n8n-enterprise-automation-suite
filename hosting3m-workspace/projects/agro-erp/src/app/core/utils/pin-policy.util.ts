/** Length of the offline unlock PIN (digits only). */
export const PIN_LENGTH = 6;

/** True only for exactly `PIN_LENGTH` ASCII digits. */
export function isPinFormat(pin: unknown): pin is string {
  return typeof pin === 'string' && new RegExp(`^\\d{${PIN_LENGTH}}$`).test(pin);
}

/**
 * Rejects trivial PINs: all the same digit, or a strictly ascending/descending run
 * (e.g. 111111, 123456, 987654). Expects a string already checked by `isPinFormat`.
 */
export function isTrivialPin(pin: string): boolean {
  const digits = pin.split('').map(Number);
  if (digits.every(d => d === digits[0])) return true;
  const steps = digits.slice(1).map((d, i) => d - digits[i]);
  return steps.every(s => s === 1) || steps.every(s => s === -1);
}
