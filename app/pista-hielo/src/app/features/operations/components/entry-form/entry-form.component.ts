import { Component, inject, signal, ViewChild, ElementRef, AfterViewInit, HostListener } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule, FormControl } from '@angular/forms';
import { Router } from '@angular/router';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';
import { PhClient } from '@core/models/client.types';
import { debounceTime, distinctUntilChanged, startWith } from 'rxjs';

type OpMode = 'FREE' | 'CLASS';

@Component({
  selector: 'app-entry-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './entry-form.component.html',
  styleUrls: ['./entry-form.component.css']
})
export class EntryFormComponent implements AfterViewInit {
  // ==========================================================
  // 1. INYECCIÓN DE DEPENDENCIAS
  // ==========================================================
  private fb = inject(FormBuilder);
  private iceService = inject(IceOperationsService);
  private router = inject(Router);

  // ==========================================================
  // 2. ESTADO DEL COMPONENTE (SIGNALS)
  // ==========================================================
  isLoading = signal(false);
  operationMode = signal<OpMode>('FREE');
  catalogsReady = this.iceService.catalogsLoaded; // Signal para el overlay de carga

  // Referencias al DOM para manejo de foco
  @ViewChild('skateInput') skateInput!: ElementRef;

  // ==========================================================
  // 3. CONTROLES DE BÚSQUEDA (TYPEAHEAD)
  // ==========================================================

  // -- Cliente --
  searchClientControl = new FormControl('');
  clientResults = signal<PhClient[]>([]);
  showClientDropdown = signal(false);
  selectedClient = signal<PhClient | null>(null);

  // -- Instructor --
  searchInstructorControl = new FormControl('');
  instructorResults = signal<any[]>([]);
  showInstructorDropdown = signal(false);
  selectedInstructor = signal<any | null>(null);

  // -- Patín --
  searchSkateControl = new FormControl('');
  skateResults = signal<any[]>([]);
  showSkateDropdown = signal(false);
  selectedSkate = signal<any | null>(null);

  // ==========================================================
  // 4. FORMULARIO PRINCIPAL
  // ==========================================================
  entryForm: FormGroup = this.fb.group({
    // Datos Lógicos (IDs Reales)
    client_id: [null],
    instructor_id_val: [null],
    skate_id_val: [null],

    // Datos Visuales (Inputs)
    skate_number: ['', Validators.required],
    notes: [''],

    // Configuración General
    client_category: ['GENERAL', Validators.required],
    duration: [60, Validators.required],

    // Configuración Clase
    rental_type: ['INSTRUCTOR']
  });

  constructor() {
    // Iniciamos descarga de datos al entrar
    this.iceService.preloadCatalogs();
    this.setupSearchListeners();
  }

  ngAfterViewInit() {
    // Foco inicial inteligente
    setTimeout(() => {
      // Opcional: Dar foco al input de patín si es lo más común
      // this.skateInput?.nativeElement?.focus(); 
    }, 200);
  }

  // ==========================================================
  // 5. MANEJO DE HOTKEYS (ACCESIBILIDAD)
  // ==========================================================
  @HostListener('window:keydown', ['$event'])
  handleKeyboardEvent(event: KeyboardEvent) {
    // F2: Guardar
    if (event.key === 'F2') {
      event.preventDefault();
      this.onSubmit();
    }
    // ESC: Limpiar
    if (event.key === 'Escape') {
      event.preventDefault();
      this.resetForm();
    }
    // Alt+1 / Alt+2: Cambiar Tabs
    if (event.altKey) {
      if (event.key === '1') { event.preventDefault(); this.setMode('FREE'); }
      if (event.key === '2') { event.preventDefault(); this.setMode('CLASS'); }

      // Atajos específicos de modo libre
      if (this.operationMode() === 'FREE') {
        if (['g', 'G'].includes(event.key)) {
          event.preventDefault();
          this.entryForm.patchValue({ client_category: 'GENERAL' });
          this.refreshSearch(); // Refrescar resultados con nueva categoría
        }
        if (['a', 'A'].includes(event.key)) {
          event.preventDefault();
          this.entryForm.patchValue({ client_category: 'ALUMNO' });
          this.refreshSearch();
        }
      }
    }
  }

  // ==========================================================
  // 6. LÓGICA DE BÚSQUEDA OPTIMIZADA (SIN PETICIONES HTTP)
  // ==========================================================
  setupSearchListeners() {
    const setupLocalSearch = (control: FormControl, resultSignal: any, dropdownSignal: any, searchFn: (term: string) => any) => {
      control.valueChanges.pipe(
        startWith(''),
        debounceTime(50), // Mínimo retardo para UI
        distinctUntilChanged()
      ).subscribe(term => {
        // Regla: No buscar si hay menos de 2 letras
        if (!term || typeof term !== 'string' || term.length < 2) {
          resultSignal.set([]);
          return;
        }

        // Ejecutar búsqueda local
        searchFn(term).subscribe((results: any[]) => {
          resultSignal.set(results);
          // Mostrar dropdown solo si el usuario está en ese input
          if (results.length > 0 && this.isControlFocused(control)) {
            dropdownSignal.set(true);
          }
        });
      });
    };

    // -- Configuración Cliente --
    setupLocalSearch(
      this.searchClientControl, this.clientResults, this.showClientDropdown,
      (term) => {
        const cat = this.operationMode() === 'CLASS' ? 'ALUMNO' : this.entryForm.get('client_category')?.value || 'GENERAL';
        return this.iceService.searchClients(term, cat);
      }
    );

    // -- Configuración Instructor --
    setupLocalSearch(
      this.searchInstructorControl, this.instructorResults, this.showInstructorDropdown,
      (term) => this.iceService.searchInstructors(term)
    );

    // -- Configuración Patín --
    setupLocalSearch(
      this.searchSkateControl, this.skateResults, this.showSkateDropdown,
      (term) => this.iceService.searchSkates(term)
    );
  }

  // Re-ejecuta la búsqueda actual (útil al cambiar categoría con teclado)
  refreshSearch() {
    this.searchClientControl.updateValueAndValidity({ emitEvent: true });
  }

  // ==========================================================
  // 7. SELECCIÓN DE ITEMS
  // ==========================================================
  selectClient(client: PhClient) {
    this.selectedClient.set(client);
    this.searchClientControl.setValue(client.full_name, { emitEvent: false });
    this.entryForm.patchValue({ client_id: client.id });
    this.showClientDropdown.set(false);
  }

  selectInstructor(ins: any) {
    this.selectedInstructor.set(ins);
    this.searchInstructorControl.setValue(ins.full_name, { emitEvent: false });
    this.entryForm.patchValue({ instructor_id_val: ins.id });
    this.showInstructorDropdown.set(false);
  }

  selectSkate(skate: any) {
    this.selectedSkate.set(skate);
    const display = skate.sku || skate.id;
    this.searchSkateControl.setValue(display, { emitEvent: false });
    this.entryForm.patchValue({ skate_number: display, skate_id_val: skate.id });
    this.showSkateDropdown.set(false);
  }

  // ==========================================================
  // 8. HELPERS DE UI
  // ==========================================================
  onFocus(dropdownSignal: any, control: FormControl) {
    if (control.value && control.value.length >= 2) {
      control.updateValueAndValidity(); // Dispara búsqueda
      dropdownSignal.set(true);
    }
  }

  onBlur(dropdownSignal: any) {
    setTimeout(() => dropdownSignal.set(false), 200); // Retardo para permitir click
  }

  isControlFocused(control: FormControl): boolean {
    const idMap: any = {
      [this.searchClientControl as any]: 'inputClient',
      [this.searchInstructorControl as any]: 'inputInstructor',
      [this.searchSkateControl as any]: 'inputSkate'
    };
    // Truco: comparamos referencia de control
    if (control === this.searchClientControl) return document.activeElement?.id === 'inputClient';
    if (control === this.searchInstructorControl) return document.activeElement?.id === 'inputInstructor';
    if (control === this.searchSkateControl) return document.activeElement?.id === 'inputSkate';
    return false;
  }

  setMode(mode: OpMode) {
    this.operationMode.set(mode);
    this.resetSearchFields();

    if (mode === 'FREE') {
      this.entryForm.patchValue({ client_category: 'GENERAL', duration: 60 });
    } else {
      this.entryForm.patchValue({ rental_type: 'INSTRUCTOR', duration: 60 });
    }
    this.refreshSearch(); // Actualizar listeners por cambio de categoría
  }

  resetSearchFields() {
    this.selectedClient.set(null); this.searchClientControl.setValue('');
    this.selectedInstructor.set(null); this.searchInstructorControl.setValue('');
    this.selectedSkate.set(null); this.searchSkateControl.setValue('');
    this.entryForm.patchValue({ client_id: null, instructor_id_val: null, skate_id_val: null, skate_number: '' });
  }

  resetForm() {
    this.entryForm.reset({ client_category: 'GENERAL', duration: 60, rental_type: 'INSTRUCTOR' });
    this.resetSearchFields();
    this.setMode('FREE');
  }

  // ==========================================================
  // 9. ENVÍO DE FORMULARIO
  // ==========================================================
  async onSubmit() {
    // 1. Validación básica de formulario
    // Nota: Ignoramos validez de skate_number si hay texto manual (tu lógica actual)
    const isSkateManual = !this.entryForm.get('skate_id_val')?.value && this.searchSkateControl.value;
    if (isSkateManual) {
      this.entryForm.patchValue({ skate_number: this.searchSkateControl.value });
    }

    if (this.entryForm.invalid || this.isLoading()) {
      this.entryForm.markAllAsTouched();
      return;
    }

    this.isLoading.set(true); // Bloqueamos UI

    try {
      const formVal = this.entryForm.value;

      // ---------------------------------------------------------
      // 🧠 LÓGICA DE AUTO-PROVISIONAMIENTO DE CLIENTE
      // ---------------------------------------------------------
      let finalClientId = formVal.client_id;
      const typedName = this.searchClientControl.value;

      // Si NO hay ID seleccionado PERO el usuario escribió un nombre (y es modo Libre)
      if (!finalClientId && typedName && typedName.length > 2 && this.operationMode() === 'FREE') {
        // Validar que no sea un nombre que ya existe en caché (evitar duplicados por error)
        const existing = this.clientResults().find(c => c.full_name.toLowerCase() === typedName.toLowerCase());

        if (existing) {
          finalClientId = existing.id; // Ya existía, lo usamos
        } else {
          // CREAR CLIENTE NUEVO AL VUELO
          const newClient = await this.iceService.createQuickClient(typedName);
          finalClientId = newClient.id;
          console.log('✨ Nuevo cliente creado al vuelo:', newClient.full_name);
        }
      }
      // ---------------------------------------------------------

      // Construimos el Payload Final
      const payload = {
        skate_number: formVal.skate_number,
        notes: formVal.notes,
        client_id: finalClientId, // Usamos el ID (existente o nuevo)
        instructor_id: formVal.instructor_id_val,
        duration: formVal.duration,
        rental_type: this.operationMode() === 'FREE'
          ? (formVal.client_category === 'ALUMNO' ? 'ALUMNO_LIBRE' : 'GENERAL_LIBRE')
          : formVal.rental_type
      };

      // Enviamos la transacción
      this.iceService.startSession(payload).subscribe({
        next: () => {
          this.isLoading.set(false);
          this.router.navigate(['/operations/monitor']);
        },
        error: (err) => {
          console.error(err);
          this.isLoading.set(false);
          alert('Error al procesar el ticket.');
        }
      });

    } catch (error) {
      console.error('❌ Error en el proceso de check-in:', error);
      this.isLoading.set(false);
      alert('No se pudo crear el cliente nuevo. Intente de nuevo.');
    }
  }
}