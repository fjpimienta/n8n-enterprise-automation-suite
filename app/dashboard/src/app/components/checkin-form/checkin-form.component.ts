import { Component, inject, input, output, OnInit } from '@angular/core';
import { FormBuilder, Validators, ReactiveFormsModule } from '@angular/forms';

@Component({
  selector: 'app-checkin-form',
  standalone: true,
  imports: [ReactiveFormsModule],
  templateUrl: './checkin-form.component.html'
})
export class CheckinForm {
  private fb = inject(FormBuilder);

  // Recibimos la habitación seleccionada
  room = input.required<any>();

  // Eventos para el dashboard
  saved = output<any>();
  canceled = output<void>();

  checkinForm = this.fb.group({
    full_name: ['', [Validators.required, Validators.minLength(3)]],
    phone: [''],
    doc_id: [''],
    check_in: [new Date().toISOString().split('T')[0]], // Hoy
    check_out: ['', Validators.required],
    total_amount: [0, Validators.required],
    notes: ['']
  });

  ngOnInit() {
    // Calculamos el Check-out sugerido (mañana) por defecto
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);

    this.checkinForm.patchValue({
      total_amount: this.room().price_night,
      check_out: tomorrow.toISOString().split('T')[0]
    });
  }

  confirmCheckin() {
    if (this.checkinForm.valid) {
      const data = {
        ...this.checkinForm.value,
        room_id: this.room().id,
        status: 'confirmed'
      };
      this.saved.emit(data);
    }
  }

  onCancel() {
    this.canceled.emit();
  }
}