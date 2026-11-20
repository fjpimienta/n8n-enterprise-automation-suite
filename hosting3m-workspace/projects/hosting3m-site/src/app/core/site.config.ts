/**
 * Public, non-secret business constants. Never add tokens, keys or tenant ids here.
 * The only credential-like value allowed in this app is the public Turnstile sitekey (added in phase 2).
 */
export const SITE = {
  name: 'Hosting3M',
  url: 'https://hosting3m.com',
  locale: 'es-MX',
  phoneDisplay: '+52 999 390 2625',
  phoneTel: '+529993902625',
  whatsappNumber: '5219993902625',
  emails: {
    general: 'contacto@hosting3m.com',
    projects: 'proyectos@hosting3m.com',
  },
  city: 'Mérida, Yucatán, México',
  ga4Id: 'G-MVJRDZ7TD8',
  githubSuiteUrl: 'https://github.com/fjpimienta/n8n-enterprise-automation-suite',
} as const;

export function whatsappLink(message: string): string {
  return `https://wa.me/${SITE.whatsappNumber}?text=${encodeURIComponent(message)}`;
}
