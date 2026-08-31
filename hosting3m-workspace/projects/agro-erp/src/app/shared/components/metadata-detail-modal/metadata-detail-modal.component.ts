import { Component, EventEmitter, Input, Output, computed, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MetadataNode, buildMetadataNodes } from '@shared/utils/metadata-view.util';

/**
 * Modal genérico (Tabler UI) que renderiza el `metadata` (JSONB) de un animal como
 * una lista de pares clave-valor legibles, sin asumir un shape fijo. Objetos y
 * arreglos anidados se muestran como sub-listas indentadas.
 */
@Component({
  selector: 'app-metadata-detail-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './metadata-detail-modal.component.html',
})
export class MetadataDetailModalComponent {
  /** `metadata` crudo tal cual llega del gateway (objeto o string JSON). */
  @Input() set metadata(value: unknown) {
    this.rawMetadata.set(value);
  }
  @Input() title = 'Detalle del animal';
  @Output() close = new EventEmitter<void>();

  private rawMetadata = signal<unknown>(null);
  public nodes = computed<MetadataNode[]>(() => buildMetadataNodes(this.rawMetadata()));
}
