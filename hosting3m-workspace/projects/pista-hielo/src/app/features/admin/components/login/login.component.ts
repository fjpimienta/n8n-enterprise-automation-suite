import { Component, inject, signal, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from 'core-auth';
import { AdminService } from '@features/admin/services/admin.service';
import { ThemeService } from '@core/services/theme.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.css']
})
export class LoginComponent implements OnInit {
  // Inyecciones
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);
  public adminService = inject(AdminService);
  public themeService = inject(ThemeService);

  // Estados UI
  isLoading = signal(false);
  showPassword = signal(false);
  errorMessage = signal<string>('');

  // 👇 NUEVO: Controlamos en qué paso del Login estamos
  step = signal<1 | 2>(1);

  // Formulario Reactivo (id_company ya no es requerido inicialmente)
  loginForm: FormGroup = this.fb.group({
    user: ['', [Validators.required]],
    pass: ['', Validators.required],
    id_company: [null]
  });

  ngOnInit() {
    // Ya no cargamos las empresas de golpe al inicio. 
    // Se cargarán cuando el usuario pase el primer filtro.
  }

  isFieldInvalid(field: string): boolean {
    const control = this.loginForm.get(field);
    return !!(control && control.invalid && (control.dirty || control.touched));
  }

  togglePassword(event: Event) {
    event.preventDefault();
    this.showPassword.update(v => !v);
  }

  // 👇 NUEVO: Botón para regresar al paso 1
  goBack() {
    this.step.set(1);
    this.errorMessage.set('');
    this.loginForm.get('id_company')?.reset();
    this.loginForm.get('id_company')?.clearValidators();
    this.loginForm.get('id_company')?.updateValueAndValidity();
  }

  onSubmit() {
    // Validación según el paso actual
    if (this.step() === 1) {
      if (this.loginForm.get('user')?.invalid || this.loginForm.get('pass')?.invalid) {
        this.loginForm.get('user')?.markAsTouched();
        this.loginForm.get('pass')?.markAsTouched();
        return;
      }
    } else {
      if (this.loginForm.get('id_company')?.invalid) {
        this.loginForm.get('id_company')?.markAsTouched();
        return;
      }
    }

    this.isLoading.set(true);
    this.errorMessage.set('');

    // Preparamos credenciales (solo enviamos id_company si estamos en el paso 2)
    const credentials = {
      user: this.loginForm.value.user,
      pass: this.loginForm.value.pass,
      ...(this.step() === 2 && { id_company: this.loginForm.value.id_company })
    };

    this.authService.login(credentials).subscribe({
      next: (res: any) => {
        this.isLoading.set(false);

        // 👇 PASO 2: El backend pide seleccionar empresa
        if (res?.status === 'select_company') {
          this.step.set(2);

          // Si el backend de n8n nos manda la lista de empresas permitidas
          if (res.data?.companies) {
            this.adminService.companies.set(res.data.companies);
          } else {
            // Fallback: Si no las manda, usamos tu método público para cargarlas
            this.adminService.loadCompanies();
          }

          // Hacemos que la sucursal sea obligatoria para continuar
          this.loginForm.get('id_company')?.setValidators([Validators.required]);
          this.loginForm.get('id_company')?.updateValueAndValidity();
          return;
        }

        // 👇 ÉXITO FINAL: Tenemos Token
        this.router.navigate(['/']);
      },
      error: (err) => {
        this.isLoading.set(false);
        console.error('Login error:', err);

        // Manejo estandarizado desde el throwError de la librería core-auth
        if (err.message === 'Credenciales inválidas' || err.status === 401) {
          this.errorMessage.set('Credenciales incorrectas. Verifique usuario y contraseña.');
        } else if (err.message === 'No tienes permisos de acceso para esta aplicación' || err.status === 403) {
          this.errorMessage.set('Acceso denegado. No tienes permisos para PistaHielo.');
        } else {
          this.errorMessage.set('No se pudo conectar con el servidor. Revise su conexión.');
        }
      }
    });
  }
}