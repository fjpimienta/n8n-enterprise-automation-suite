import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { AuthService } from '../../services/auth.service';
import { Router } from '@angular/router';
import { LoggerService } from '../../services/logger.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule], // Importamos módulos necesarios
  templateUrl: './login.component.html',
  styleUrl: './login.component.css'
})
export class LoginComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);
  private logger = inject(LoggerService);

  loginForm: FormGroup = this.fb.group({
    user: ['', Validators.required],
    pass: ['', Validators.required]
  });

  onSubmit() {
    if (this.loginForm.valid) {
      this.logger.log('Intentando iniciar sesión con:', this.loginForm.value.user);
      this.authService.login(this.loginForm.value).subscribe({
        next: (res) => {
          this.logger.log('Login exitoso');
          this.router.navigate(['/dashboard']);
        },
        error: (err) => {
          this.logger.error('Fallo el login', err); // Solo se verá en desarrollo
          alert('Credenciales incorrectas');
        }
      });
    }
  }
}