import { Component, input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SearchableView } from '@shared/utils/paged-table.util';

/**
 * Barra de herramientas reutilizable sobre una tabla paginada: buscador (si
 * `pagedTable().searchEnabled`) + un slot de proyección para filtros propios de cada tabla
 * (select de "Falta", de "Estado", etc. — cada tabla decide los suyos, este componente no los
 * conoce) + un botón opcional de exportar CSV, solo si el consumidor provee `onExportCsv`.
 */
@Component({
  selector: 'app-table-toolbar',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './table-toolbar.component.html'
})
export class TableToolbarComponent {
  public pagedTable = input.required<SearchableView>();
  public searchPlaceholder = input<string>('Buscar...');
  /** Omitir para no mostrar el botón de CSV — ninguna de las tablas de esta fase lo usa todavía. */
  public onExportCsv = input<(() => void) | null>(null);

  public setSearch(value: string): void {
    this.pagedTable().setSearchQuery(value);
  }
}
