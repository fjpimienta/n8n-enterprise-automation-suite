import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { lastValueFrom } from 'rxjs';
import { AdminService } from '@features/admin/services/admin.service';
import { UppFormModalComponent } from '../upp-form-modal/upp-form-modal.component';
import { AuthService, TenantService, TenantContext } from 'core-auth';
import { isPhantomRow } from '@core/utils/gateway-empty-row.util';

@Component({
  selector: 'app-tenant-list',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, UppFormModalComponent],
  templateUrl: './tenant-list.component.html',
  styleUrl: './tenant-list.component.scss',
})
export class TenantListComponent {
  public adminService = inject(AdminService);
  public tenantService = inject(TenantService);
  private authService = inject(AuthService);

  // Solo las empresas a las que el usuario tiene acceso (resueltas en el login multi-tenant)
  tenants = this.tenantService.availableTenants;

  searchQuery = signal<string>('');

  filteredTenants = computed(() => {
    const q = this.searchQuery().toLowerCase();
    return this.tenants().filter(t => !q || t.company_name?.toLowerCase().includes(q));
  });

  isModalOpen = signal<boolean>(false);
  isLoadingDetail = signal<boolean>(false);
  isReadOnlyMode = signal<boolean>(false);
  selectedUpp = signal<any>(null);
  currentUppData = signal<any>({});

  canEdit(tenant: TenantContext): boolean {
    return tenant.role === 'ADMIN';
  }

  /**
   * UPP/lot management is only reachable for the active tenant: the tenant interceptor
   * always sends the active tenant as `x-tenant-id`, so any other card would show the
   * wrong tenant's data. Switching tenants stays an explicit action of the tenant selector.
   */
  isActiveTenant(tenant: TenantContext): boolean {
    return Number(tenant.id_company) === Number(this.tenantService.activeTenantId());
  }

  async openModal(tenant: TenantContext | null = null) {
    if (tenant) {
      this.isLoadingDetail.set(true);
      this.isReadOnlyMode.set(!this.canEdit(tenant));
      try {
        const res: any = await lastValueFrom(this.adminService.getCompanyById(tenant.id_company));
        // The gateway's getone returns `data` as a single object, not an array. Never fall back
        // to the cached TenantContext: it has no metadata, and saving from it would overwrite
        // the company's whole metadata JSONB with only the fields edited in this session.
        const fullCompany = Array.isArray(res?.data) ? res.data[0] : res?.data;
        if (res?.error || isPhantomRow(fullCompany, 'id_company')) {
          throw new Error(res?.message || 'Empresa no encontrada.');
        }
        this.selectedUpp.set(fullCompany);
        this.currentUppData.set({ ...fullCompany, metadata: { ...fullCompany.metadata } });
        this.isModalOpen.set(true);
      } catch (error) {
        console.error('[Agro-ERP] Error al cargar detalle de la empresa:', error);
        alert('❌ No se pudo cargar la información de la empresa.');
      } finally {
        this.isLoadingDetail.set(false);
      }
    } else {
      this.isReadOnlyMode.set(false);
      this.selectedUpp.set(null);
      this.currentUppData.set(this.getEmptyUpp());
      this.isModalOpen.set(true);
    }
  }

  closeModal() {
    this.isModalOpen.set(false);
    this.selectedUpp.set(null);
  }

  async saveUpp() {
    if (this.isReadOnlyMode()) return;

    const data = this.currentUppData();
    const operation: 'insert' | 'update' = this.selectedUpp() ? 'update' : 'insert';

    if (!data.company_name) {
      alert('⚠️ El Nombre del Rancho es obligatorio.');
      return;
    }

    try {
      // Only real `companys` columns edited by the modal; never TenantContext-only keys (role, business_type).
      const fields = {
        company_name: data.company_name,
        ...(operation === 'insert' ? { industry: data.industry } : {}),
        metadata: data.metadata ?? {}
      };
      const res: any = await lastValueFrom(
        this.adminService.saveCompany(fields, operation, this.selectedUpp()?.id_company)
      );
      // Postgres errors arrive as HTTP 200 with `error: true`.
      if (res?.error) throw new Error(res.message);

      if (operation === 'insert') {
        const created = res.data?.[0];
        const email = this.authService.currentUser()?.email;

        if (created && email) {
          await lastValueFrom(
            this.adminService.saveUserCompany(email, created.id_company, 'ADMIN', true, 'insert')
          );

          const newTenant: TenantContext = {
            id_company: created.id_company,
            company_name: created.company_name,
            role: 'ADMIN',
            industry: created.industry || 'GANADERIA',
            business_type: 'LIVESTOCK'
          };
          this.tenantService.setAvailableTenants([...this.tenantService.availableTenants(), newTenant]);
        }
      }

      if (operation === 'update') {
        this.syncTenantName(this.selectedUpp().id_company, data.company_name);
      }

      alert(operation === 'insert' ? '✅ Empresa registrada correctamente' : '✅ Empresa actualizada correctamente');
      this.closeModal();
    } catch (error) {
      console.error('[Agro-ERP] Error al guardar la empresa:', error);
      alert('❌ Error al guardar el registro en la base de datos.');
    }
  }

  /** Cards and the tenant selector read the cached login context; keep the renamed company in sync. */
  private syncTenantName(idCompany: number, companyName: string) {
    const rename = (t: TenantContext) =>
      Number(t.id_company) === Number(idCompany) ? { ...t, company_name: companyName } : t;

    this.tenantService.setAvailableTenants(this.tenantService.availableTenants().map(rename));
    const active = this.tenantService.activeTenant();
    if (active && Number(active.id_company) === Number(idCompany)) {
      this.tenantService.setActiveTenant(rename(active));
    }
  }

  private getEmptyUpp() {
    return {
      company_name: '',
      industry: 'GANADERIA',
      metadata: {}
    };
  }
}
