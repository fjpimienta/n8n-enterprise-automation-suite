// Importamos Zone.js (vital para que Angular detecte cambios en los tests)
import 'zone.js';
import 'zone.js/testing';

// --- MOCK GLOBAL PARA matchMedia ---
// Esto engaña al navegador de pruebas (JSDOM) para que crea que soporta media queries.
// --- PARCHE MANUAL PARA VITEST/JSDOM ---
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: (query: any) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }),
});
// ---------------------------------------