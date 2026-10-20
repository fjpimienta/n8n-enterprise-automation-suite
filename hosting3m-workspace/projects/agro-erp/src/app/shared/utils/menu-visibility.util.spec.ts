import { describe, expect, it } from 'vitest';
import { menuVisibility } from './menu-visibility.util';

const palm = (role: string) => ({ industry: 'Agricultura de Precisión', role });
const cattle = (role: string) => ({ industry: 'Ganadería de Precisión', role });

describe('menuVisibility', () => {
  it('palm ADMIN: palm entries and shared config, no livestock entries, "Personal"', () => {
    expect(menuVisibility(palm('ADMIN'))).toEqual({
      livestockIntelligence: false, palmIntelligence: true, palmAdministration: true, palmExpenses: true,
      sharedConfig: true, livestockConfig: false, intelligenceSection: true, configSection: true,
      personalLabel: 'Personal',
    });
  });

  it('palm EDITOR: no administration and no empty "Configuración" section', () => {
    const v = menuVisibility(palm('EDITOR'));
    expect(v.palmIntelligence).toBe(true);
    expect(v.palmAdministration).toBe(false);
    expect(v.livestockConfig).toBe(false);
    expect(v.configSection).toBe(false);
  });

  it('palm OWNER administers plantations but sees no ADMIN-only configuration', () => {
    const v = menuVisibility(palm('OWNER'));
    expect(v.palmAdministration).toBe(true);
    expect(v.configSection).toBe(false);
  });

  it('livestock ADMIN: livestock entries and catalogs, nothing of palm, "Personal UPP"', () => {
    expect(menuVisibility(cattle('ADMIN'))).toEqual({
      livestockIntelligence: true, palmIntelligence: false, palmAdministration: false, palmExpenses: false,
      sharedConfig: true, livestockConfig: true, intelligenceSection: true, configSection: true,
      personalLabel: 'Personal UPP',
    });
  });

  it('livestock EDITOR: intelligence only, no empty configuration section', () => {
    const v = menuVisibility(cattle('EDITOR'));
    expect(v.livestockIntelligence).toBe(true);
    expect(v.configSection).toBe(false);
  });

  it('unknown domain keeps the historical configuration for ADMIN and hides the empty intelligence title', () => {
    const v = menuVisibility({ industry: 'Generic', role: 'ADMIN' });
    expect(v.intelligenceSection).toBe(false);
    expect(v.livestockConfig).toBe(true);
    expect(v.personalLabel).toBe('Personal UPP');
  });

  it('palm "Gastos": ADMIN, OWNER and EDITOR capture; CUSTOMER and livestock companies never see it', () => {
    expect(menuVisibility(palm('ADMIN')).palmExpenses).toBe(true);
    expect(menuVisibility(palm('OWNER')).palmExpenses).toBe(true);
    expect(menuVisibility(palm('editor')).palmExpenses).toBe(true);
    expect(menuVisibility(palm('CUSTOMER')).palmExpenses).toBe(false);
    expect(menuVisibility(cattle('ADMIN')).palmExpenses).toBe(false);
    expect(menuVisibility({ industry: 'Generic', role: 'ADMIN' }).palmExpenses).toBe(false);
  });

  it('no active company: nothing visible', () => {
    const v = menuVisibility(null);
    expect(v.intelligenceSection || v.configSection || v.palmAdministration || v.palmExpenses).toBe(false);
  });
});
