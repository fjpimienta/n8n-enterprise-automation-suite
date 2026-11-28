import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

/** Stroke paths on a 24x24 grid (Tabler-style outline icons, MIT). Decorative: pair with a text label. */
export const H_ICON_PATHS = {
  grid: ['M4 4h6v8h-6z', 'M14 4h6v4h-6z', 'M14 12h6v8h-6z', 'M4 16h6v4h-6z'],
  tool: ['M7 10h3v-3l-3.5 -3.5a6 6 0 0 1 8 8l6 6a2 2 0 0 1 -3 3l-6 -6a6 6 0 0 1 -8 -8l3.5 3.5'],
  calendar: ['M4 7a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-12z', 'M16 3v4', 'M8 3v4', 'M4 11h16'],
  users: ['M9 7m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0', 'M3 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2', 'M16 3.13a4 4 0 0 1 0 7.75', 'M21 21v-2a4 4 0 0 0 -3 -3.85'],
  'user-check': ['M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0', 'M6 21v-2a4 4 0 0 1 4 -4h4', 'M15 19l2 2l4 -4'],
  user: ['M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0', 'M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2'],
  box: ['M12 3l8 4.5v9l-8 4.5l-8 -4.5v-9l8 -4.5', 'M12 12l8 -4.5', 'M12 12v9', 'M12 12l-8 -4.5'],
  wallet: ['M17 8v-3a1 1 0 0 0 -1 -1h-10a2 2 0 0 0 0 4h12a1 1 0 0 1 1 1v3m0 4v3a1 1 0 0 1 -1 1h-12a2 2 0 0 1 -2 -2v-12', 'M20 12v4h-4a2 2 0 0 1 0 -4h4'],
  sun: ['M12 12m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0', 'M3 12h1', 'M12 3v1', 'M20 12h1', 'M12 20v1', 'M5.6 5.6l.7 .7', 'M18.4 5.6l-.7 .7', 'M17.7 17.7l.7 .7', 'M6.3 17.7l-.7 .7'],
  moon: ['M12 3c.132 0 .263 0 .393 0a7.5 7.5 0 0 0 7.92 12.446a9 9 0 1 1 -8.313 -12.454z'],
  logout: ['M14 8v-2a2 2 0 0 0 -2 -2h-7a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h7a2 2 0 0 0 2 -2v-2', 'M9 12h12l-3 -3', 'M18 15l3 -3'],
  login: ['M15 8v-2a2 2 0 0 0 -2 -2h-7a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h7a2 2 0 0 0 2 -2v-2', 'M21 12h-13l3 -3', 'M11 15l-3 -3'],
  plus: ['M12 5v14', 'M5 12h14'],
  menu: ['M4 6h16', 'M4 12h16', 'M4 18h16'],
  more: ['M5 12h.01', 'M12 12h.01', 'M19 12h.01'],
  brush: ['M3 21v-4a4 4 0 1 1 4 4h-4', 'M21 3a16 16 0 0 0 -12.8 10.2', 'M21 3a16 16 0 0 1 -10.2 12.8', 'M10.6 9a9 9 0 0 1 4.4 4.4'],
  'chevron-down': ['M6 9l6 6l6 -6'],
  search: ['M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0', 'M21 21l-6 -6'],
  x: ['M18 6l-12 12', 'M6 6l12 12'],
  refresh: ['M20 11a8.1 8.1 0 0 0 -15.5 -2m-.5 -4v4h4', 'M4 13a8.1 8.1 0 0 0 15.5 2m.5 4v-4h-4'],
  eye: ['M10 12a2 2 0 1 0 4 0a2 2 0 0 0 -4 0', 'M21 12c-2.4 4 -5.4 6 -9 6c-3.6 0 -6.6 -2 -9 -6c2.4 -4 5.4 -6 9 -6c3.6 0 6.6 2 9 6'],
  'eye-off': ['M3 3l18 18', 'M10.584 10.587a2 2 0 0 0 2.828 2.83', 'M9.363 5.365a9.466 9.466 0 0 1 2.637 -.365c3.6 0 6.6 2 9 6c-.666 1.11 -1.379 2.067 -2.138 2.87', 'M6.632 6.62c-1.9 1.4 -3.5 3.4 -4.632 5.38c2.4 4 5.4 6 9 6a9.5 9.5 0 0 0 4.38 -1.04'],
  alert: ['M12 9v4', 'M10.363 3.591l-8.106 13.534a1.914 1.914 0 0 0 1.636 2.871h16.214a1.914 1.914 0 0 0 1.636 -2.87l-8.106 -13.536a1.914 1.914 0 0 0 -3.274 0z', 'M12 16h.01'],
  building: ['M3 21l18 0', 'M5 21v-14l8 -4l8 4v14', 'M9 9l0 .01', 'M9 12l0 .01', 'M9 15l0 .01', 'M9 18l0 .01'],
  lock: ['M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6z', 'M8 11v-4a4 4 0 1 1 8 0v4'],
  bed: ['M3 7v11', 'M3 14h18', 'M21 18v-8a2 2 0 0 0 -2 -2h-9v6', 'M7 11h.01']
} as const;

export type HIconName = keyof typeof H_ICON_PATHS;

@Component({
  selector: 'app-h-icon',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<svg class="h-icon" [attr.width]="size()" [attr.height]="size()" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
      @for (d of paths(); track $index) { <path [attr.d]="d" /> }
    </svg>`
})
export class HIconComponent {
  readonly name = input.required<HIconName>();
  readonly size = input<number>(20);
  protected readonly paths = computed<readonly string[]>(() => H_ICON_PATHS[this.name()] ?? []);
}
