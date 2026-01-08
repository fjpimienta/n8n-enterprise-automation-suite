import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { AuthService } from '../../services/auth.service';
import { Router } from '@angular/router';

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

  loginForm: FormGroup = this.fb.group({
    user: ['', Validators.required],
    pass: ['', Validators.required]
  });

  onSubmit() {
    if (this.loginForm.valid) {
      // 1. Mostramos que estamos cargando (opcional)
      console.log('Intentando login para:', this.loginForm.value.user);

      this.authService.login(this.loginForm.value).subscribe({
        next: (res) => {
          // res contiene { token: '...', role: '...' } enviado por n8n
          console.log('Login exitoso en n8n:', res);

          // 2. Redirigimos al Dashboard
          this.router.navigate(['/dashboard']);
        },
        error: (err) => {
          console.error('Error de login:', err);
          // Si n8n devuelve 401 o 403, mostramos alerta
          alert('Usuario o contraseña incorrectos');
        }
      });
    }
  }
}