import { Component, Output, EventEmitter, input, OnInit, inject, ChangeDetectorRef } from '@angular/core';
import { FormGroup, FormControl, Validators, ReactiveFormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { Room } from '@core/models/hotel.types';
import { AdminService } from '@features/admin/services/admin.service';

@Component({
  selector: 'app-checkin-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './checkin-form.component.html'
})
export class CheckinFormComponent implements OnInit {
  private adminService = inject(AdminService);
  private cdr = inject(ChangeDetectorRef);

  room = input.required<Room | null>();
  reservation = input<any | null>(null);

  @Output() saved = new EventEmitter<any>();
  @Output() onClose = new EventEmitter<void>();

  activeRes: any = null;
  standardPrice: number = 0;
  discountAmount: number = 0;
  daysCount: number = 1;

  checkinForm = new FormGroup({
    full_name: new FormControl('', [Validators.required]),
    phone: new FormControl(''),
    email: new FormControl('', [Validators.email]),
    doc_id: new FormControl(''),
    city: new FormControl(''),
    state: new FormControl(''),
    country: new FormControl('México'),
    check_out: new FormControl('', [Validators.required]),
    total_amount: new FormControl(0, [Validators.required, Validators.min(0)]),
    initial_payment_type: new FormControl('pending'),
    amount_paid: new FormControl<number | null>(0, [Validators.min(0)]),
    vip_status: new FormControl(false),
    requires_invoice: new FormControl(false),
    is_invoiced: new FormControl(false),
    notes: new FormControl('')
  });

  ngOnInit() {
    this.checkinForm.get('check_out')?.valueChanges.subscribe(() => {
      this.calculateStandardPrice();
      this.cdr.detectChanges();
    });

    this.checkinForm.get('total_amount')?.valueChanges.subscribe((val) => {
      this.calculateDiscount(val || 0);
      // Si está en modo "Cobrado Total", actualizamos el abono automáticamente
      if (this.checkinForm.get('initial_payment_type')?.value === 'full') {
        this.checkinForm.patchValue({ amount_paid: val || 0 }, { emitEvent: false });
      }
      this.cdr.detectChanges();
    });

    // 🧠 MÁQUINA DE ESTADOS DE UI: Reacciona al cambio de modalidad de pago
    this.checkinForm.get('initial_payment_type')?.valueChanges.subscribe(mode => {
      const total = this.checkinForm.get('total_amount')?.value || 0;
      if (mode === 'full') {
        this.checkinForm.patchValue({ amount_paid: total }, { emitEvent: false });
      } else if (mode === 'pending') {
        this.checkinForm.patchValue({ amount_paid: 0 }, { emitEvent: false });
      } else if (mode === 'partial') {
        const currentPaid = this.checkinForm.get('amount_paid')?.value;
        if (currentPaid === total || currentPaid === 0) {
          this.checkinForm.patchValue({ amount_paid: null }, { emitEvent: false }); // Limpiamos para que escriba
        }
      }
    });

    this.checkinForm.get('is_invoiced')?.valueChanges.subscribe(() => {
      this.calculateStandardPrice();
      this.cdr.detectChanges();
    });

    let passedRes = this.reservation();
    const currentRoom = this.room();

    if (passedRes && passedRes.id) {
      this.activeRes = passedRes;
    } else if (currentRoom) {
      const allRes = this.adminService.reservations();
      const now = new Date();
      const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

      this.activeRes = allRes.find(r => {
        if (Number(r.room_id) !== Number(currentRoom.id)) return false;

        const status = String(r.status || '').toLowerCase().trim();
        if (!['confirmed', 'pending'].includes(status)) return false;

        const inStr = String(r.check_in).split(/[ T]/)[0];
        const outStr = String(r.check_out).split(/[ T]/)[0];

        return inStr <= todayStr && outStr >= todayStr;
      });
    }

    if (this.activeRes) {
      this.fillWithReservationData(this.activeRes);
    } else {
      this.initDefaultValues();
      this.calculateStandardPrice();
    }

    this.cdr.detectChanges();
  }

  calculateStandardPrice() {
    const roomData = this.room();
    const checkOutDate = this.checkinForm.get('check_out')?.value;

    if (roomData && checkOutDate) {
      let startDateStr = new Date().toISOString().split('T')[0];
      const res = this.activeRes;

      if (res && res.check_in) {
        startDateStr = String(res.check_in).split(/[ T]/)[0];
      }

      const start = new Date(startDateStr + 'T00:00:00');
      const end = new Date(checkOutDate + 'T00:00:00');

      const diffTime = end.getTime() - start.getTime();
      this.daysCount = Math.max(1, Math.ceil(diffTime / (1000 * 60 * 60 * 24)));

      const basePrice = this.daysCount * (roomData.price_night || 0);
      const wantsInvoice = this.checkinForm.get('is_invoiced')?.value;

      this.standardPrice = wantsInvoice ? (basePrice * 1.18) : basePrice;

      const currentTotal = this.checkinForm.get('total_amount')?.value;
      if (!res || currentTotal === 0 || currentTotal === null) {
        this.checkinForm.patchValue({ total_amount: this.standardPrice }, { emitEvent: false });
        this.calculateDiscount(this.standardPrice);
      } else {
        this.calculateDiscount(currentTotal || 0);
      }
    }
  }

  calculateDiscount(amountCharged: number) {
    this.discountAmount = Math.max(0, this.standardPrice - amountCharged);
    const notesControl = this.checkinForm.get('notes');
    if (this.discountAmount > 0) {
      notesControl?.addValidators(Validators.required);
    } else {
      notesControl?.removeValidators(Validators.required);
    }
    notesControl?.updateValueAndValidity({ emitEvent: false });
  }

  private initDefaultValues() {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const dateString = tomorrow.toISOString().split('T')[0];

    this.checkinForm.patchValue({
      check_out: dateString,
      full_name: '',
      phone: '',
      email: '',
      doc_id: '',
      city: '',
      state: '',
      country: 'México',
      total_amount: 0,
      initial_payment_type: 'pending',
      amount_paid: 0,
      vip_status: false,
      requires_invoice: false,
      is_invoiced: false,
      notes: ''
    }, { emitEvent: false });
  }

  private fillWithReservationData(res: any) {
    if (!res) return;

    const guestData = res.hotel_guests_data || res.guest || {};

    let docId = guestData.doc_id || res.guest_doc_id || '';
    if (docId.startsWith('INT-')) docId = '';

    let email = guestData.email || res.guest_email || '';
    if (email.startsWith('no-email-')) email = '';

    let checkOutStr = '';
    if (res.check_out) {
      checkOutStr = String(res.check_out).split(/[ T]/)[0];
    }

    // Calcular estado inicial basado en abonos previos
    const total = res.total_amount || 0;
    const paid = res.amount_paid || 0;
    let paymentType = 'pending';

    if (paid >= total && total > 0) paymentType = 'full';
    else if (paid > 0) paymentType = 'partial';

    this.checkinForm.patchValue({
      full_name: guestData.full_name || res.guest_name || '',
      phone: guestData.phone || res.guest_phone || '',
      email: email,
      doc_id: docId,
      city: guestData.city || '',
      state: guestData.state || '',
      country: guestData.country || 'México',
      check_out: checkOutStr,
      total_amount: total,
      initial_payment_type: paymentType,
      amount_paid: paid,
      vip_status: guestData.vip_status || false,
      requires_invoice: res.is_invoiced || false,
      is_invoiced: res.is_invoiced || false,
      notes: res.notes || ''
    });

    setTimeout(() => {
      this.calculateStandardPrice();
      if (res.total_amount !== undefined) {
        this.checkinForm.patchValue({ total_amount: res.total_amount });
      }
    });
  }

  confirmCheckin() {
    const formVal = this.checkinForm.getRawValue(); // Obtenemos valores incluso si están bloqueados

    if (!formVal.doc_id || formVal.doc_id.trim() === '') {
      this.checkinForm.patchValue({ doc_id: this.adminService.generateInternalId() });
    }

    if (!formVal.email || formVal.email.trim() === '') {
      this.checkinForm.patchValue({ email: this.adminService.generateDummyEmail() });
    }

    const finalVal = this.checkinForm.getRawValue();

    // 🛑 BLINDAJE MATEMÁTICO ANTES DE ENVIAR
    if (finalVal.initial_payment_type === 'partial') {
      const paid = Number(finalVal.amount_paid) || 0;
      const total = Number(finalVal.total_amount) || 0;

      if (paid <= 0) {
        alert('❌ El anticipo debe ser mayor a $0.');
        return;
      }
      if (paid >= total) {
        alert('❌ El anticipo no puede ser igual o mayor al total. Si desea liquidar la cuenta completa, seleccione la opción "Liquida Ahora".');
        return;
      }
    }

    if (this.checkinForm.valid) {
      // Inyectamos el cálculo matemático forzado para que nunca viaje un 0 accidental
      const payload = {
        ...finalVal,
        amount_paid: finalVal.initial_payment_type === 'full' ? finalVal.total_amount :
          finalVal.initial_payment_type === 'pending' ? 0 : finalVal.amount_paid,
        guest_id: this.activeRes?.guest_id || null,
        discount_amount: this.discountAmount
      };

      this.saved.emit(payload);
    } else {
      this.checkinForm.markAllAsTouched();
    }
  }

  closeCheckinModal() {
    this.onClose.emit();
  }
}