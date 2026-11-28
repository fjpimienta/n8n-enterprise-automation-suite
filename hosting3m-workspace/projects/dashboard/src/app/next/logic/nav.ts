import type { HIconName } from '../../shared/ui/h-icon/h-icon.component';

export interface NavLink { label: string; route: string; icon: HIconName; adminOnly: boolean }
export interface NavGroup { title: string; links: NavLink[] }

const NAV: NavGroup[] = [
  { title: 'Operaciones', links: [
    { label: 'Panel', route: '/dashboard', icon: 'grid', adminOnly: false },
    { label: 'Limpieza', route: '/dashboard/limpieza', icon: 'brush', adminOnly: false },
    { label: 'Mantenimiento', route: '/dashboard/mantenimiento', icon: 'tool', adminOnly: false },
    { label: 'Reservas', route: '/dashboard/reservas', icon: 'calendar', adminOnly: false }
  ] },
  { title: 'Administración', links: [
    { label: 'Huéspedes', route: '/dashboard/huespedes', icon: 'users', adminOnly: false },
    { label: 'Personal', route: '/dashboard/personal', icon: 'user-check', adminOnly: true },
    { label: 'Inventario', route: '/dashboard/inventario', icon: 'box', adminOnly: true }
  ] },
  { title: 'Finanzas', links: [
    { label: 'Caja y gastos', route: '/dashboard/finanzas', icon: 'wallet', adminOnly: true }
  ] }
];

/** Menu for the `next` shell. Mirrors the ADMIN-only route guards: those entries are hidden for everyone else. */
export function buildNav(isAdmin: boolean): NavGroup[] {
  return NAV
    .map(g => ({ title: g.title, links: g.links.filter(l => !l.adminOnly || isAdmin) }))
    .filter(g => g.links.length > 0);
}

const TITLES: Record<string, string> = {
  '/dashboard': 'Panel de operación',
  '/dashboard/limpieza': 'Limpieza',
  '/dashboard/mantenimiento': 'Mantenimiento',
  '/dashboard/reservas': 'Reservas',
  '/dashboard/huespedes': 'Huéspedes',
  '/dashboard/personal': 'Personal',
  '/dashboard/inventario': 'Inventario',
  '/dashboard/finanzas': 'Caja y gastos'
};

export function pageTitle(url: string): string {
  const path = url.split(/[?#]/)[0].replace(/\/+$/, '') || '/dashboard';
  return TITLES[path] ?? 'Hotel San José';
}
