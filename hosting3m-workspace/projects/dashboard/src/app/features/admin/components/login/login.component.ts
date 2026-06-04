import { CommonModule } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';

import { LoggerService } from '../../services/logger.service';
import { AuthService, TenantService, CompanyContext } from 'core-auth';
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
  private tenantService = inject(TenantService);
  private router = inject(Router);
  private logger = inject(LoggerService);
  public themeService = inject(ThemeService);

  isLoading = signal(false);
  showPassword = signal(false);
  errorMessage = signal<string>('');

  availableCompanies = signal<CompanyContext[]>([]);
  showCompanySelection = signal(false);

  // Inicia deshabilitado, forzando la validación del backend en el paso 1
  loginForm: FormGroup = this.fb.group({
    user: ['', Validators.required],
    pass: ['', Validators.required],
    id_company: [{ value: '', disabled: true }, Validators.required]
  });

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

      const rawPayload = this.loginForm.getRawValue();

      this.authService.login(rawPayload).subscribe({
        next: (res: any) => {
          if (res.status === 'select_company' && res.data?.companies) {
            this.logger.log('⚠️ Múltiples sucursales detectadas. Activando selector.');
            this.isLoading.set(false);
            this.availableCompanies.set(res.data.companies);
            this.showCompanySelection.set(true);
            this.loginForm.get('id_company')?.enable();
          } else {
            this.logger.log('✅ Login autorizado. Sincronizando contexto global del hotel.');
            this.isLoading.set(false);

            const activeCompany = res.data?.company || this.authService.currentUser();
            if (activeCompany) {
              this.tenantService.setActiveTenant({
                id_company: activeCompany.id_company,
                company_name: activeCompany.company_name || 'Hotel San José',
                role: activeCompany.role,
                industry: 'Hotelera'
              });
            }
            this.router.navigate(['/dashboard']);
          }
        },
        error: (err: any) => {
          this.isLoading.set(false);
          this.logger.error('❌ Acceso denegado', err);
          if (err.status === 401 || err.status === 403) {
            this.errorMessage.set(err.message || 'Usuario o contraseña incorrectos.');
          } else {
            this.errorMessage.set('Error de conexión. Intente más tarde.');
          }
        }
      });
    } else {
      this.loginForm.markAllAsTouched();
    }
  }
}