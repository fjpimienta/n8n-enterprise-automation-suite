import { Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import { ProductionUnitSummary } from '@core/models/production-unit-lot.model';
import { ProductionUnitLotService } from '@features/admin/services/production-unit-lot.service';

/**
 * UPPs (`production_units`) of the ACTIVE tenant — entry point to each UPP's lots.
 * `activeTenantRouteGuard` already rejects a `:tenantId` other than the active one; the
 * effect below also leaves the page if the active tenant changes while it is open.
 */
@Component({
  selector: 'app-production-unit-list',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './production-unit-list.component.html',
})
export class ProductionUnitListComponent {
  private lotService = inject(ProductionUnitLotService);
  private tenantService = inject(TenantService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  /** Route param. Display/navigation only — never sent to the API. */
  tenantId = toSignal(this.route.paramMap.pipe(map(p => p.get('tenantId'))));

  activeTenant = this.tenantService.activeTenant;

  units = signal<ProductionUnitSummary[]>([]);
  isLoading = signal<boolean>(false);
  loadError = signal<string | null>(null);
  searchQuery = signal<string>('');

  filteredUnits = computed(() => {
    const q = this.searchQuery().toLowerCase();
    return this.units().filter(u =>
      !q || u.ranchName.toLowerCase().includes(q) || u.uppCode.toLowerCase().includes(q)
    );
  });

  constructor() {
    effect(() => {
      const activeId = this.tenantService.activeTenantId();
      if (!activeId || String(activeId) !== String(this.tenantId() ?? activeId)) {
        untracked(() => this.router.navigate(['/admin/tenants']));
        return;
      }
      untracked(() => this.load());
    });
  }

  async load() {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      this.units.set(await this.lotService.getProductionUnits());
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cargar las UPP:', error);
      this.loadError.set(error?.message || 'No se pudieron cargar las unidades de producción.');
      this.units.set([]);
    } finally {
      this.isLoading.set(false);
    }
  }
}
