import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CashRegisterService } from '@features/admin/services/cash-register.service';

@Component({
  selector: 'app-shift-report',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './shift-report.component.html',
  styleUrls: ['./shift-report.component.css']
})
export class ShiftReportComponent implements OnInit {
  // Inyectamos el servicio como público para usarlo directo en el HTML
  public cashService = inject(CashRegisterService);

  ngOnInit() {
    // Al cargar la pantalla, pedimos el corte del día
    this.cashService.loadDailyReport();
  }

  printReport() {
    // Abre el diálogo de impresión del navegador
    window.print();
  }
}