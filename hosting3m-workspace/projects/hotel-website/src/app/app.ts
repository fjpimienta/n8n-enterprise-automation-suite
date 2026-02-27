import { Component, OnInit, inject, signal, HostListener } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { AiChatComponent } from 'ui-chat';
import { environment } from '../environments/environment';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule, AiChatComponent],
  templateUrl: './app.html'
})
export class App implements OnInit {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl_crud;

  // 1. Estados de la Interfaz (LO QUE FALTABA)
  isMenuOpen = signal(false);
  isScrolled = signal(false);

  // 2. Estado del formulario (Ya lo tenías)
  lead = { name: '', email: '', phone: '', checkin: '', checkout: '', guests: '2' };
  isSubmitting = signal(false);
  formStatus = signal<'idle' | 'success' | 'error'>('idle');

  ngOnInit() {
    setTimeout(() => {
      // @ts-ignore
      if (window.lucide) window.lucide.createIcons();
    }, 100);
  }

  // 👇 LÓGICA DEL SCROLL (Equivalente a tu window.addEventListener)
  @HostListener('window:scroll', [])
  onWindowScroll() {
    this.isScrolled.set(window.scrollY > 20);
  }

  // 👇 LÓGICA DEL MENÚ MÓVIL (Equivalente a tu btnMenu.addEventListener)
  toggleMenu() {
    this.isMenuOpen.update(val => !val);
  }

  // Tu función submitForm() se queda exactamente igual abajo...
  submitForm() {
    this.isSubmitting.set(true);
    this.formStatus.set('idle');

    const payload = {
      ...this.lead,
      origen: "Web Frontend Angular",
      timestamp: new Date().toISOString()
    };

    this.http.post(this.apiUrl, payload).subscribe({
      next: () => {
        this.formStatus.set('success');
        this.lead = { name: '', email: '', phone: '', checkin: '', checkout: '', guests: '2' };
      },
      error: () => {
        this.formStatus.set('error');
      },
      complete: () => {
        this.isSubmitting.set(false);
      }
    });
  }
}