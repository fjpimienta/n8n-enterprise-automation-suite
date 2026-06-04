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
    // Si ya mostramos el selector, validamos que tenga una empresa elegida
    if (this.showCompanySelection() && !this.loginForm.value.id_company) {
      this.errorMessage.set('Por favor, selecciona un entorno de trabajo.');
      return;
    }

    if (this.loginForm.valid) {
      this.isLoading.set(true);

      // getRawValue() incluirá el id_company, incluso si estaba deshabilitado antes
      const payload = this.loginForm.getRawValue();

      this.authService.login(payload).subscribe({
        next: (res: any) => {
          if (res.status === 'select_company') {
            // Ya sabemos que esto funciona:
            this.availableCompanies.set(res.data.companies);
            this.showCompanySelection.set(true);
            this.loginForm.get('id_company')?.enable();
            this.isLoading.set(false);
          } else if (res.status === 'success') {
            // ¡Aquí está la clave! 
            // Al llegar aquí con un payload que ya tiene id_company,
            // n8n debe retornar el token final.
            this.isLoading.set(false);
            this.router.navigate(['/dashboard']);
          }
        },
        error: (err) => {
          this.isLoading.set(false);
          this.errorMessage.set('Error en la autenticación final.');
        }
      });
    }
  }
}