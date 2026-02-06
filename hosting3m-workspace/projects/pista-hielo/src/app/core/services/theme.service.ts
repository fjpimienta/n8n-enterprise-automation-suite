import { Injectable, signal, effect, inject, PLATFORM_ID } from '@angular/core';
import { DOCUMENT, isPlatformBrowser } from '@angular/common'; // <--- IMPORTANTE

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  // Inyectamos el ID de la plataforma para detectar Servidor vs Navegador
  private platformId = inject(PLATFORM_ID);
  // Inyectamos DOCUMENT para manipular el body de forma segura
  private document = inject(DOCUMENT);

  // Señal para el estado: 'light' o 'dark'
  currentTheme = signal<'light' | 'dark'>('light');

  constructor() {
    // PASO 1: Verificamos si estamos en el Navegador antes de tocar LocalStorage
    if (isPlatformBrowser(this.platformId)) {

      const savedTheme = localStorage.getItem('theme') as 'light' | 'dark';

      if (savedTheme) {
        this.currentTheme.set(savedTheme);
      } else {
        // Detectar preferencia del sistema operativo (Solo existe en navegador)
        const systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        this.currentTheme.set(systemDark ? 'dark' : 'light');
      }
    }

    // PASO 2: El efecto también debe protegerse
    effect(() => {
      const theme = this.currentTheme();

      // Solo intentamos modificar el DOM y LocalStorage si estamos en el navegador
      if (isPlatformBrowser(this.platformId)) {
        this.document.body.setAttribute('data-bs-theme', theme);
        localStorage.setItem('theme', theme);
      }
    });
  }

  toggleTheme() {
    this.currentTheme.update(t => t === 'light' ? 'dark' : 'light');
  }
}