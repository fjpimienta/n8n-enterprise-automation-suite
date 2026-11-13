import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { TenantService } from 'core-auth';
import { PlantationContextService } from '../services/plantation-context.service';
import { SaleTab, canManageSales, saleTabsFor } from '../utils/sale.util';
import { SaleBalanceComponent } from './sale-balance.component';
import { SaleListComponent } from './sale-list.component';

const TAB_LABELS: Record<SaleTab, string> = { RESUMEN: 'Resumen', VENTAS: 'Ventas registradas' };

/**
 * "Ventas" of the active palm company (migrations 104, 105 and 107). ADMIN only, by the role of the ACTIVE company
 * (re-checked live: a role or company change leaves the screen at once). Sales are registered from a voucher in the chat;
 * here they are summarized, listed and voided. The gateway answers 403 to anyone else regardless.
 */
@Component({
  selector: 'app-sale-page',
  standalone: true,
  imports: [SaleBalanceComponent, SaleListComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './sale-page.component.html',
})
export class SalePageComponent {
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  private role = computed(() => this.tenantService.activeTenant()?.role);
  allowed = computed(() => canManageSales(this.role()));
  tabs = computed(() => saleTabsFor(this.role()));
  activeTab = signal<SaleTab>('RESUMEN');
  /** Bumped after a void so the open tab (and the other one when shown) reloads. */
  refreshToken = signal(0);
  readonly tabLabels = TAB_LABELS;

  constructor() {
    // The role of the active company can change without reloading: keep the active tab valid.
    effect(() => {
      const tabs = this.tabs();
      if (tabs.length && !tabs.includes(this.activeTab())) this.activeTab.set(tabs[0]);
    });
  }
}
