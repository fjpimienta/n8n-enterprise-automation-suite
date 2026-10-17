import { describe, expect, it } from 'vitest';
import {
  LIVESTOCK_DASHBOARD_ROUTE,
  PALM_DASHBOARD_ROUTE,
  dashboardRouteFor,
  isLivestockDomain,
  isPalmDomain,
  livestockRouteRedirect,
  palmRouteRedirect,
  resolveBusinessDomain,
  themeClassFor,
} from './business-domain.util';

describe('resolveBusinessDomain', () => {
  it('detects palm by industry, with or without accents and case', () => {
    expect(resolveBusinessDomain({ industry: 'Agricultura de Precisión' })).toBe('PALM');
    expect(resolveBusinessDomain({ industry: '  AGRICULTURA  ' })).toBe('PALM');
  });

  it('detects livestock by industry, including the test tenant 3 label', () => {
    expect(resolveBusinessDomain({ industry: 'Ganadería de Precisión' })).toBe('LIVESTOCK');
    expect(resolveBusinessDomain({ industry: 'Servicio de Renta de Pista de Hielo y Ganadería' })).toBe('LIVESTOCK');
    expect(resolveBusinessDomain({ industry: 'ganaderia' })).toBe('LIVESTOCK');
  });

  it('an explicit business_type wins over the industry text', () => {
    expect(resolveBusinessDomain({ business_type: 'AGRICULTURE', industry: 'Ganadería' })).toBe('PALM');
    expect(resolveBusinessDomain({ business_type: 'LIVESTOCK', industry: 'Agricultura' })).toBe('LIVESTOCK');
  });

  it('the login fallback business_type ADMIN does not decide; the industry does', () => {
    expect(resolveBusinessDomain({ business_type: 'ADMIN', industry: 'Agricultura de Precisión' })).toBe('PALM');
    expect(resolveBusinessDomain({ business_type: 'ADMIN', industry: 'Generic' })).toBe('UNKNOWN');
  });

  it('an industry mentioning both prefers palm (more specific label)', () => {
    expect(resolveBusinessDomain({ industry: 'Agricultura y Ganadería' })).toBe('PALM');
  });

  it('is fail-safe with missing data', () => {
    expect(resolveBusinessDomain(null)).toBe('UNKNOWN');
    expect(resolveBusinessDomain(undefined)).toBe('UNKNOWN');
    expect(resolveBusinessDomain({})).toBe('UNKNOWN');
    expect(resolveBusinessDomain({ industry: null, business_type: null })).toBe('UNKNOWN');
  });
});

describe('domain helpers', () => {
  it('isPalmDomain / isLivestockDomain are mutually exclusive', () => {
    const palm = { industry: 'Agricultura de Precisión' };
    const cattle = { industry: 'Ganadería de Precisión' };
    expect([isPalmDomain(palm), isLivestockDomain(palm)]).toEqual([true, false]);
    expect([isPalmDomain(cattle), isLivestockDomain(cattle)]).toEqual([false, true]);
  });

  it('dashboardRouteFor lands each domain on its own dashboard (unknown -> livestock, historical default)', () => {
    expect(dashboardRouteFor({ industry: 'Agricultura de Precisión' })).toBe(PALM_DASHBOARD_ROUTE);
    expect(dashboardRouteFor({ industry: 'Ganadería de Precisión' })).toBe(LIVESTOCK_DASHBOARD_ROUTE);
    expect(dashboardRouteFor(null)).toBe(LIVESTOCK_DASHBOARD_ROUTE);
  });

  it('palm screens: only palm passes; livestock / unknown go to their own dashboard', () => {
    expect(palmRouteRedirect({ industry: 'Agricultura de Precisión' })).toBeNull();
    expect(palmRouteRedirect({ industry: 'Ganadería de Precisión' })).toBe(LIVESTOCK_DASHBOARD_ROUTE);
    expect(palmRouteRedirect({ industry: 'Generic' })).toBe(LIVESTOCK_DASHBOARD_ROUTE);
    expect(palmRouteRedirect(null)).toBe(LIVESTOCK_DASHBOARD_ROUTE);
  });

  it('livestock screens: livestock and unknown pass (as today); palm goes to the palm dashboard', () => {
    expect(livestockRouteRedirect({ industry: 'Ganadería de Precisión' })).toBeNull();
    expect(livestockRouteRedirect({ industry: 'Servicio de Renta de Pista de Hielo y Ganadería' })).toBeNull();
    expect(livestockRouteRedirect({ industry: 'Generic' })).toBeNull();
    expect(livestockRouteRedirect(null)).toBeNull();
    expect(livestockRouteRedirect({ industry: 'Agricultura de Precisión' })).toBe(PALM_DASHBOARD_ROUTE);
    expect(livestockRouteRedirect({ business_type: 'AGRICULTURE' })).toBe(PALM_DASHBOARD_ROUTE);
  });

  it('themeClassFor follows the domain', () => {
    expect(themeClassFor({ industry: 'Agricultura' })).toBe('theme-palm');
    expect(themeClassFor({ industry: 'Ganadería' })).toBe('theme-cattle');
    expect(themeClassFor(null)).toBe('theme-cattle');
  });
});
