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

  // 🚀 Signals para resolver las propiedades faltantes en la UI
  availableCompanies = signal<CompanyContext[]>([]);
  showCompanySelection = signal(false);

  // El campo id_company inicia deshabilitado hasta que el backend requiera selección
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

  // En tu método onSubmit, actualiza la lógica para incluir el id_company si existe:
  onSubmit() {
  if (this.loginForm.valid) {
    this.isLoading.set(true);
    this.errorMessage.set('');

    // Extraemos los valores del formulario
    const credentials = this.loginForm.getRawValue();

    this.authService.login(credentials).subscribe({
      next: (res: any) => {
        // Escenario A: Selección de empresa requerida
        if (res.status === 'select_company') {
          this.isLoading.set(false);
          this.availableCompanies.set(res.data.companies);
          this.showCompanySelection.set(true);
          this.loginForm.get('id_company')?.enable();
        } 
        // Escenario B: Login exitoso (AuthService ya actualizó los signals internamente)
        else if (res.status === 'success') {
          this.isLoading.set(false);
          this.router.navigate(['/dashboard']);
        }
      },
      error: (err) => {
        this.isLoading.set(false);
        this.errorMessage.set(err.message || 'Error de conexión');
      }
    });
  }
}
}