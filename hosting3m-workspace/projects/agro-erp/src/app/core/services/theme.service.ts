import { Injectable, signal, effect } from '@angular/core';

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  // 1. Iniciamos la señal estrictamente en 'dark'
  currentTheme = signal<'light' | 'dark'>('dark');

  constructor() {
    // 2. Buscamos si el usuario ya guardó una preferencia antes
    const savedTheme = localStorage.getItem('theme') as 'light' | 'dark';
    if (savedTheme) {
      this.currentTheme.set(savedTheme);
    } else {
      // 3. Si no hay tema guardado, forzamos el oscuro por default
      this.currentTheme.set('dark');
    }

    // 4. Efecto mágico: Actualiza el HTML automáticamente
    effect(() => {
      const theme = this.currentTheme();
      document.body.setAttribute('data-bs-theme', theme);
      localStorage.setItem('theme', theme);
    });
  }

  toggleTheme() {
    this.currentTheme.update(t => t === 'light' ? 'dark' : 'light');
  }
}