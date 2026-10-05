import { Component, input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PagerView } from '@shared/utils/paged-table.util';

/**
 * Pie de tabla reutilizable — "Mostrando X–Y de N" (siempre visible, incluso con N=0) +
 * selector de tamaño y navegación de página (ocultos solo si `pagedTable().showPager()` es
 * false, p.ej. menos filas que `minRowsToShowPager`). El consumidor nunca envuelve este
 * componente en un `@if` propio — la visibilidad condicional vive adentro.
 */
@Component({
  selector: 'app-table-footer',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './table-footer.component.html'
})
export class TableFooterComponent {
  public pagedTable = input.required<PagerView>();
}
