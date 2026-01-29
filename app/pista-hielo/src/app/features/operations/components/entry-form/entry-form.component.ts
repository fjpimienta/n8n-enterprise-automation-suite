import { Component, inject, signal, ViewChild, ElementRef, AfterViewInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';

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

  entryForm: FormGroup = this.fb.group({
    client_type: ['GENERAL', Validators.required], // Valor por defecto
    skate_number: ['', [Validators.required, Validators.pattern('^[0-9]*$')]],
    notes: ['']
  });

  // Poner el foco en el input numérico al cargar (para escanear código de barras o teclear rápido)
  ngAfterViewInit() {
    setTimeout(() => this.skateInput.nativeElement.focus(), 100);
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

    this.iceService.startSession(this.entryForm.value).subscribe({
      next: (res) => {
        // Éxito: Vamos al monitor para ver la tarjeta creada
        this.isLoading.set(false);
        this.router.navigate(['/operations/monitor']);

        // TODO: Aquí podrías mostrar un Toast de éxito ("Patín #24 Registrado")
      },
      error: (err) => {
        console.error(err);
        this.isLoading.set(false);
        alert('Error al registrar la entrada. Revise la conexión.');
      }
    });
  }
}