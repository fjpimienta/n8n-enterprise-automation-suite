/**
 * Single source of truth for the legal entity, address and opening hours. The footer, the contact section, the
 * terms page and the schema.org JSON-LD all read from here: edit these values only in this file.
 */
export const BUSINESS = {
  legalName: 'Francisco Jesus Perez Pimienta',
  address: {
    street: 'Calle 12D #895, Fracc. Solana',
    locality: 'Mérida',
    region: 'Yucatán',
    country: 'MX',
  },
  /** Machine-readable (schema.org openingHours), Central Mexico time. */
  openingHours: ['Mo-Fr 09:00-17:00', 'Sa 09:00-14:00'],
  /** Human-readable versions of the same hours. */
  hoursText: 'Lunes a viernes de 9:00 a 17:00 y sábados de 9:00 a 14:00 (hora del Centro de México)',
  hoursShort: 'L-V 9:00-17:00 · Sáb 9:00-14:00',
} as const;

export const BUSINESS_ADDRESS_LINE = `${BUSINESS.address.street}, ${BUSINESS.address.locality}, ${BUSINESS.address.region}`;
