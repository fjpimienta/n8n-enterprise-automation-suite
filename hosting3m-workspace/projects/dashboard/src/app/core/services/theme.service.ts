// src/app/core/services/theme.service.ts
import { Injectable, signal, effect } from '@angular/core';

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  // Señal para el estado: 'light' o 'dark'
  currentTheme = signal<'light' | 'dark'>('light');

  constructor() {
    // 1. Cargar preferencia guardada o usar default
    const savedTheme = localStorage.getItem('theme') as 'light' | 'dark';
    if (savedTheme) {
      this.currentTheme.set(savedTheme);
    } else {
      // Opcional: Detectar preferencia del sistema operativo
      const systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      this.currentTheme.set(systemDark ? 'dark' : 'light');
    }

    // 2. Efecto mágico: Cada vez que cambie la señal, actualizamos el HTML
    effect(() => {
      const theme = this.currentTheme();
      document.body.setAttribute('data-bs-theme', theme); // Esto activa el modo oscuro de Tabler
      localStorage.setItem('theme', theme);
    });
  }

  toggleTheme() {
    this.currentTheme.update(t => t === 'light' ? 'dark' : 'light');
  }
}