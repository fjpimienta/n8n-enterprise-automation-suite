import { Component, inject, signal, effect, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common'; // Necesario para pipes async si usas
import { AuthService } from '@core/auth/auth.service';
import { AdminService } from '@features/admin/services/admin.service';

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
  public adminService = inject(AdminService); // Público para usarlo en el HTML

  // Estado UI
  isLoading = signal(false);
  showPassword = signal(false);
  errorMessage = signal<string>('');

  // Formulario Reactivo
  loginForm: FormGroup = this.fb.group({
    id_company: ['', Validators.required],
    user: ['', [Validators.required]],
    pass: ['', Validators.required]
  });

  constructor() {
    // Efecto: Cuando carguen las empresas, seleccionar la default automáticamente
    effect(() => {
      const list = this.adminService.companies();
      if (list.length > 0) {
        const defaultComp = list.find(c => c.is_default);
        if (defaultComp) {
          this.loginForm.patchValue({ id_company: defaultComp.id_company });
        }
      }
    });
  }

  ngOnInit() {
    this.adminService.loadCompanies();
  }

  // Helper para validación visual
  isFieldInvalid(field: string): boolean {
    const control = this.loginForm.get(field);
    return !!(control && control.invalid && (control.dirty || control.touched));
  }

  togglePassword(event: Event) {
    event.preventDefault(); // Evita que el botón haga submit
    this.showPassword.update(v => !v);
  }

  onSubmit() {
    if (this.loginForm.invalid) {
      this.loginForm.markAllAsTouched();
      return;
    }

    this.isLoading.set(true);
    this.errorMessage.set('');

    const credentials = {
      user: this.loginForm.value.user,
      pass: this.loginForm.value.pass
    };

    this.authService.login(this.loginForm.value).subscribe({
      next: () => {
        // La redirección ya la hace el AuthService
        this.isLoading.set(false);
      },
      error: (err) => {
        this.isLoading.set(false);
        console.error('Login error:', err);
        if (err.status === 401) {
          this.errorMessage.set('Credenciales incorrectas. Verifique usuario y contraseña.');
        } else {
          this.errorMessage.set('No se pudo conectar con el servidor. Revise su conexión.');
        }
      }
    });
  }
}