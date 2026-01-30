import { Component, inject, signal, ViewChild, ElementRef, AfterViewInit, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';

type OpMode = 'FREE' | 'CLASS';

@Component({
  selector: 'app-entry-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './entry-form.component.html',
  styleUrls: ['./entry-form.component.css']
})
export class EntryFormComponent implements AfterViewInit {
  private fb = inject(FormBuilder);
  private iceService = inject(IceOperationsService);
  private router = inject(Router);

  @ViewChild('skateInput') skateInput!: ElementRef;

  isLoading = signal(false);

  // Señal para controlar las pestañas
  operationMode = signal<OpMode>('FREE');

  // Formulario unificado con todos los campos posibles
  entryForm: FormGroup = this.fb.group({
    // Campos comunes
    skate_number: ['', [Validators.required, Validators.pattern('^[0-9]*$')]],
    notes: [''],

    // Campos dinámicos (se cambian validators según el modo)
    rental_type: ['GENERAL', Validators.required],
    instructor_id: ['']
  });

  constructor() {
    // Efecto (opcional): Si quisieras reaccionar a cambios de modo, pero lo manejamos en setMode
  }

  ngAfterViewInit() {
    setTimeout(() => this.skateInput?.nativeElement?.focus(), 100);
  }

  // Cambio de Pestaña
  setMode(mode: OpMode) {
    this.operationMode.set(mode);

    if (mode === 'FREE') {
      // Configurar para Patinaje Libre
      this.entryForm.patchValue({ rental_type: 'GENERAL', instructor_id: '' });
      this.entryForm.get('instructor_id')?.clearValidators();
    } else {
      // Configurar para Clase
      this.entryForm.patchValue({ rental_type: 'INSTRUCTOR' });
      this.entryForm.get('instructor_id')?.setValidators(Validators.required);
    }

    this.entryForm.get('instructor_id')?.updateValueAndValidity();

    // Devolver el foco al input principal
    setTimeout(() => this.skateInput?.nativeElement?.focus(), 50);
  }

  isFieldInvalid(field: string): boolean {
    const control = this.entryForm.get(field);
    return !!(control && control.invalid && (control.touched || control.dirty));
  }

  onSubmit() {
    if (this.entryForm.invalid) {
      this.entryForm.markAllAsTouched();
      return;
    }

    this.isLoading.set(true);

    // Mapeamos los datos para enviarlos al backend
    const payload = {
      ...this.entryForm.value,
      // Si estamos en modo clase, nos aseguramos que el tipo sea correcto
      mode: this.operationMode()
    };

    this.iceService.startSession(payload).subscribe({
      next: (res) => {
        this.isLoading.set(false);
        this.router.navigate(['/operations/monitor']);
      },
      error: (err) => {
        console.error(err);
        this.isLoading.set(false);
        // Aquí podrías usar un Toast service
        alert('Error al conectar con el servidor.');
      }
    });
  }
}