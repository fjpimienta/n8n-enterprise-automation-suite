import { CommonModule } from '@angular/common';
import { Component, inject, signal, effect } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../../services/auth.service';
import { LoggerService } from '../../services/logger.service';
import { HotelService } from '../../services/hotel.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './login.component.html'
})
export class LoginComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);
  private logger = inject(LoggerService);
  public hotelService = inject(HotelService);

  // Estados reactivos con Signals (Angular 19 Best Practice)
  isLoading = signal(false);
  showPassword = signal(false);
  errorMessage = signal<string>('');

  loginForm: FormGroup = this.fb.group({
    user: ['', Validators.required],
    pass: ['', Validators.required],
    id_company: ['', Validators.required]
  });

  constructor() {
    // Creamos un efecto que reacciona cuando el signal de empresas cambia
    effect(() => {
      const list = this.hotelService.companies();
      if (list.length > 0) {
        // Buscamos la que tenga is_default true
        const defaultComp = list.find(c => c.is_default === true);

        if (defaultComp) {
          // Parchamos el formulario con el ID de la empresa por defecto
          this.loginForm.patchValue({ id_company: defaultComp.id_company });
        }
      }
    });
  }

  ngOnInit() {
    this.hotelService.loadCompanies();
    this.loginForm.get('id_company')?.disable();
  }

  // Helper para validación visual en HTML
  isFieldInvalid(field: string): boolean {
    const control = this.loginForm.get(field);
    return !!(control && control.invalid && (control.dirty || control.touched));
  }

  // Toggle para ver contraseña
  togglePassword(event: Event) {
    event.preventDefault();
    this.showPassword.update(value => !value);
  }

  onSubmit() {
    if (this.loginForm.valid) {
      // 1. Activar estado de carga y limpiar errores
      this.isLoading.set(true);
      this.errorMessage.set('');

      this.logger.log('🔐 Iniciando handshake de seguridad para:', this.loginForm.value.user);

      this.authService.login(this.loginForm.value).subscribe({
        next: (res) => {
          this.logger.log('✅ Login autorizado. Token recibido.');
          // Importante: HotelService usa 'authToken', asegúrate de usar esa misma llave
          localStorage.setItem('authToken', res.data.token);
          this.router.navigate(['/dashboard']);
          // No seteamos isLoading false aquí porque navegamos fuera
        },
        error: (err) => {
          this.isLoading.set(false);
          this.logger.error('❌ Acceso denegado', err);

          // Mensaje amigable para el usuario final
          if (err.status === 401 || err.status === 403) {
            this.errorMessage.set('Usuario o contraseña incorrectos.');
          } else {
            this.errorMessage.set('Error de conexión con el servidor. Intente más tarde.');
          }
        }
      });
    } else {
      this.loginForm.markAllAsTouched(); // Marca los campos rojos si intenta enviar vacío
    }
  }

}