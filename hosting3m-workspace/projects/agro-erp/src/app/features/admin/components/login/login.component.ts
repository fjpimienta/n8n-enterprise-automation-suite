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
    if (this.loginForm.invalid) {
      this.loginForm.markAllAsTouched();
      return;
    }

    this.isLoading.set(true);
    this.errorMessage.set('');

    const payload = this.loginForm.getRawValue();

    this.authService.login(payload).subscribe({
      next: (res: any) => {
        this.isLoading.set(false);
        // Paso 1: El backend solicita resolución de contexto (Multi-Tenant)
        const companies = res.data?.companies || [];

        // En LoginComponent.ts -> onSubmit -> next -> status === 'success'

        if (companies && companies.length > 0) {
          this.tenantService.setAvailableTenants(companies);

          // AÑADE ESTO AQUÍ MISMO:
          this.tenantService.debugState();

          if (!this.tenantService.activeTenant()) {
            this.tenantService.setActiveTenant(companies[0]);
          }
        }

        if (res.status === 'select_company' && companies) {
          // this.logger.log('res.data:', res.data);
          this.availableCompanies.set(res.data.companies);
          this.showCompanySelection.set(true);
          this.loginForm.get('id_company')?.enable();
        }
        // Paso 2: Autenticación e inserción de sesión exitosa
        else if (res.status === 'success') {
          // this.logger.log('✅ Acceso autorizado. Sincronizando tenant activo.');
          // this.logger.log('res.data:', res.data);

          if (res.data) {
            const companies = res.data.companies;
            if (companies && companies.length > 0) {
              this.tenantService.setAvailableTenants(companies);
              // Opcional: auto-seleccionar el primero si no hay uno activo
              if (!this.tenantService.activeTenant()) {
                this.tenantService.setActiveTenant(companies[0]);
              }
            }
            this.logger.log('companies:', companies);
          }

          const activeCompany = res.data?.company;
          if (activeCompany) {
            this.tenantService.setActiveTenant({
              id_company: activeCompany.id_company,
              company_name: activeCompany.company_name,
              role: activeCompany.role,
              industry: activeCompany.industry || 'Generic',
              business_type: activeCompany.business_type || 'ADMIN'
            });
          }
          this.router.navigate(['/dashboard']);
        }
      },
      error: (err) => {
        this.isLoading.set(false);
        this.logger.error('❌ Error de autenticación:', err);
        this.errorMessage.set(err.message || 'Error de comunicación con el servidor.');
      }
    });
  }
}