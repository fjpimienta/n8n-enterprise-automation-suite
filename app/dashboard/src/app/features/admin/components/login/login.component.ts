import { CommonModule } from '@angular/common';
import { Component, inject, signal, effect } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';

import { LoggerService } from '../../services/logger.service';
import { AuthService } from '@core/services/auth.service';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { AdminService } from '@features/admin/services/admin.service';
import { ThemeService } from '@core/services/theme.service';

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
  public adminService = inject(AdminService);
  public themeService = inject(ThemeService);

  isLoading = signal(false);
  showPassword = signal(false);
  errorMessage = signal<string>('');

  loginForm: FormGroup = this.fb.group({
    user: ['', Validators.required],
    pass: ['', Validators.required],
    id_company: ['', Validators.required]
  });

  constructor() {
    effect(() => {
      const list = this.adminService.companies();
      if (list.length > 0) {
        const defaultComp = list.find(c => c.is_default === true);

        if (defaultComp) {
          this.loginForm.patchValue({ id_company: defaultComp.id_company });
        }
      }
    });
  }

  ngOnInit() {
    this.adminService.loadCompanies();
    this.loginForm.get('id_company')?.disable();
  }

  isFieldInvalid(field: string): boolean {
    const control = this.loginForm.get(field);
    return !!(control && control.invalid && (control.dirty || control.touched));
  }

  togglePassword(event: Event) {
    event.preventDefault();
    this.showPassword.update(value => !value);
  }

  onSubmit() {
    if (this.loginForm.valid) {
      this.isLoading.set(true);
      this.errorMessage.set('');

      // Llamamos al login
      this.authService.login(this.loginForm.value).subscribe({
        next: (res) => {
          this.logger.log('✅ Login autorizado. Token recibido.');

          // ELIMINADO: this.authService.login(res.data.token); (Esto estaba mal y causaba error)
          // ELIMINADO: localStorage.setItem... (El servicio ya lo hace en el tap)

          // Solo navegamos, la reactividad del servicio hará el resto
          this.router.navigate(['/dashboard']);
        },
        error: (err) => {
          this.isLoading.set(false);
          this.logger.error('❌ Acceso denegado', err);

          if (err.status === 401 || err.status === 403) {
            this.errorMessage.set('Usuario o contraseña incorrectos.');
          } else {
            this.errorMessage.set('Error de conexión con el servidor. Intente más tarde.');
          }
        }
      });
    } else {
      this.loginForm.markAllAsTouched();
    }
  }

}