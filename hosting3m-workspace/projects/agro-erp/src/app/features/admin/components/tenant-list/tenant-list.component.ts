import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { lastValueFrom } from 'rxjs';
import { AdminService } from '@features/admin/services/admin.service';
import { UppFormModalComponent } from '../upp-form-modal/upp-form-modal.component';
import { AuthService, TenantService, TenantContext } from 'core-auth';

@Component({
  selector: 'app-tenant-list',
  standalone: true,
  imports: [CommonModule, FormsModule, UppFormModalComponent],
  templateUrl: './tenant-list.component.html',
  styleUrl: './tenant-list.component.scss',
})
export class TenantListComponent {
  public adminService = inject(AdminService);
  public tenantService = inject(TenantService);
  private authService = inject(AuthService);

  // Solo las UPP a las que el usuario tiene acceso (resueltas en el login multi-tenant)
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

  async openModal(tenant: TenantContext | null = null) {
    if (tenant) {
      this.isLoadingDetail.set(true);
      this.isReadOnlyMode.set(!this.canEdit(tenant));
      try {
        const res = await lastValueFrom(this.adminService.getCompanyById(tenant.id_company));
        const fullCompany = res.data?.[0] ?? tenant;
        this.selectedUpp.set(fullCompany);
        this.currentUppData.set({ ...fullCompany, metadata: { ...fullCompany.metadata } });
        this.isModalOpen.set(true);
      } catch (error) {
        console.error('[Agro-ERP] Error al cargar detalle de UPP:', error);
        alert('❌ No se pudo cargar la información de la UPP.');
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
      const res = await lastValueFrom(
        this.adminService.saveCompany(data, operation, this.selectedUpp()?.id_company)
      );

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

      alert(operation === 'insert' ? '✅ UPP registrada correctamente' : '✅ UPP actualizada correctamente');
      this.closeModal();
    } catch (error) {
      console.error('[Agro-ERP] Error al guardar la UPP:', error);
      alert('❌ Error al guardar el registro en la base de datos.');
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
