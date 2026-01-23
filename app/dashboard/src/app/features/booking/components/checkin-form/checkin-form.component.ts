import { Component, Output, EventEmitter, input, OnInit, OnChanges, SimpleChanges, effect } from '@angular/core';
import { FormGroup, FormControl, Validators, ReactiveFormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { Room } from '@core/models/hotel.types';

@Component({
  selector: 'app-checkin-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './checkin-form.component.html'
})
export class CheckinFormComponent implements OnInit, OnChanges {
  room = input.required<Room | null>();
  reservation = input<any | null>(null);

  @Output() saved = new EventEmitter<any>();
  @Output() canceled = new EventEmitter<void>();
  @Output() onClose = new EventEmitter<void>();

  checkinForm = new FormGroup({
    full_name: new FormControl('', [Validators.required]),
    phone: new FormControl(''),
    email: new FormControl('', [Validators.email]),
    doc_id: new FormControl('', [Validators.required]),
    city: new FormControl(''),
    state: new FormControl(''),
    country: new FormControl('México'),
    check_out: new FormControl('', [Validators.required]),
    total_amount: new FormControl(0, [Validators.min(0)]),
    vip_status: new FormControl(false),
    requires_invoice: new FormControl(false),
    notes: new FormControl('')
  });

  ngOnInit() {
    this.initDefaultValues();

    this.checkinForm.get('check_out')?.valueChanges.subscribe(() => {
      this.calculateTotal();
    });
  }

  ngOnChanges(changes: SimpleChanges) {
    if (changes['reservation'] && this.reservation()) {
      this.fillWithReservationData(this.reservation());
    }
  }

  private fillWithReservationData(res: any) {
    if (!res) return;
    const guest = res.hotel_guests_data || res.guest || {};
    let docId = guest.doc_id || res.guest_doc_id || '';
    let email = guest.email || res.guest_email || '';
    if (docId && docId.startsWith('INT-')) {
      docId = '';
    }
    if (email && email.startsWith('no-email-')) {
      email = '';
    }
    this.checkinForm.patchValue({
      full_name: guest.full_name || res.guest_name || '',
      phone: guest.phone || res.guest_phone || '',
      email: email,
      doc_id: docId,
      city: guest.city || '',
      state: guest.state || '',
      country: guest.country || 'México',
      check_out: res.check_out ? res.check_out.split('T')[0] : '',
      total_amount: res.total_amount || 0,
      vip_status: guest.vip_status || false,
      requires_invoice: guest.requires_invoice || false,
      notes: res.notes || ''
    });
    this.calculateTotal();
  }

  private initDefaultValues() {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const dateString = tomorrow.toISOString().split('T')[0];

    this.checkinForm.patchValue({
      check_out: dateString
    });
    this.calculateTotal();
  }

  calculateTotal() {
    const roomData = this.room();
    const checkOutDate = this.checkinForm.get('check_out')?.value;

    if (roomData && checkOutDate) {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const end = new Date(checkOutDate);

      /** Calcular diferencia en días (mínimo 1 día) */ 
      const diffTime = end.getTime() - start.getTime();
      const diffDays = Math.max(1, Math.ceil(diffTime / (1000 * 60 * 60 * 24)));

      const total = diffDays * (roomData.price_night || 0);
      this.checkinForm.patchValue({ total_amount: total }, { emitEvent: false });
    }
  }

  confirmCheckin() {
    if (this.checkinForm.valid) {
      this.saved.emit(this.checkinForm.value);
    } else {
      this.checkinForm.markAllAsTouched();
    }
  }

  closeCheckinModal() {
    this.onClose.emit();
  }
}