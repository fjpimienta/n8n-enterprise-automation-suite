import { Component, inject, signal, computed, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { lastValueFrom } from 'rxjs';
import { AdminService } from '@features/admin/services/admin.service';
import { UserFormModalComponent } from '../user-form-modal/user-form-modal.component';
import { AuthService, TenantService } from 'core-auth';
import { CompanyMember, MemberFormData } from '@core/models/company-member.model';
import { resolveCurrentUserEmail } from '@shared/utils/authorization-actions.util';
import {
  MEMBER_ROLE_OPTIONS,
  buildUpdateFields,
  canEditProfile,
  gatewayErrorMessage,
  interpretAccessResponse,
  isSelf,
  resolveAddMemberResult,
  resolveUpdateMemberResult,
  roleLabel,
  validateMemberForm
} from '@shared/utils/member-access.util';

const NETWORK_ERROR_MESSAGE = 'No se pudo conectar con el servicio de personal. Intenta de nuevo.';

/**
 * Personal UPP: members of the ACTIVE company. Every write goes through sp_access_* (migration 073),
 * which enforce role, company and last-ADMIN rules; nothing is ever deleted (deactivate/reactivate).
 */
@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [CommonModule, FormsModule, UserFormModalComponent],
  templateUrl: './user-list.component.html',
  styleUrl: './user-list.component.css',
})
export class UserListComponent {
  public adminService = inject(AdminService);
  public tenantService = inject(TenantService);
  private authService = inject(AuthService);

  readonly roleOptions = MEMBER_ROLE_OPTIONS;
  readonly roleLabel = roleLabel;

  members = this.adminService.members;
  currentUserEmail = computed(() => resolveCurrentUserEmail(this.authService.currentUser() as any));

  searchQuery = signal<string>('');
  roleFilter = signal<string>('ALL');

  filteredMembers = computed(() => {
    const q = this.searchQuery().trim().toLowerCase();
    const role = this.roleFilter();
    return this.members().filter(m => {
      const matchesQuery = !q ||
        m.names?.toLowerCase().includes(q) ||
        m.lastname?.toLowerCase().includes(q) ||
        m.email?.toLowerCase().includes(q);
      const matchesRole = role === 'ALL' || m.role === role;
      return matchesQuery && matchesRole;
    });
  });

  isModalOpen = signal<boolean>(false);
  selectedMember = signal<CompanyMember | null>(null);
  formData = signal<MemberFormData>(this.emptyForm());
  profileEditable = computed(() => canEditProfile(this.selectedMember(), this.currentUserEmail()));
  roleLocked = computed(() => {
    const member = this.selectedMember();
    return !!member && isSelf(member, this.currentUserEmail());
  });

  isSubmitting = signal<boolean>(false);
  modalError = signal<string | null>(null);
  successMessage = signal<string | null>(null);
  errorMessage = signal<string | null>(null);

  constructor() {
    // Reloads on every company switch; only an ADMIN of the active company may list its members.
    effect(() => {
      const activeTenant = this.tenantService.activeTenant();
      this.adminService.members.set([]);
      this.successMessage.set(null);
      this.errorMessage.set(null);
      if (activeTenant?.role === 'ADMIN') {
        this.adminService.loadMembers();
      }
    }, { allowSignalWrites: true });
  }

  isSelf(member: CompanyMember): boolean {
    return isSelf(member, this.currentUserEmail());
  }

  openModal(member: CompanyMember | null = null) {
    this.selectedMember.set(member);
    this.formData.set(member
      ? {
          email: member.email,
          names: member.names ?? '',
          lastname: member.lastname ?? '',
          phone: member.phone ?? '',
          role: (member.role === 'OWNER' ? 'ADMIN' : member.role),
          password: ''
        }
      : this.emptyForm());
    this.modalError.set(null);
    this.isModalOpen.set(true);
  }

  closeModal() {
    if (this.isSubmitting()) return;
    this.isModalOpen.set(false);
    this.selectedMember.set(null);
  }

  async saveMember() {
    if (this.isSubmitting()) return;
    const member = this.selectedMember();
    const data = this.formData();

    const validationError = validateMemberForm(data, member, this.currentUserEmail());
    if (validationError) {
      this.modalError.set(validationError);
      return;
    }

    this.isSubmitting.set(true);
    this.modalError.set(null);
    try {
      const res = await lastValueFrom(member
        ? this.adminService.updateMember(buildUpdateFields(data, member, this.currentUserEmail()))
        : this.adminService.addMember(data));

      // Fail-closed (MetaCRUD Silent Error Shield): only an explicit SP success closes the modal; an
      // HTTP 200 with `error: true`, an empty body or any n8n failure payload keeps it open in red.
      const result = member ? resolveUpdateMemberResult(res) : resolveAddMemberResult(res);
      if (!result.ok) {
        this.modalError.set(result.message);
        return;
      }

      this.successMessage.set(result.message);
      this.errorMessage.set(null);
      this.isSubmitting.set(false);
      this.closeModal();
      this.adminService.loadMembers();
    } catch (error) {
      this.modalError.set(gatewayErrorMessage(error, NETWORK_ERROR_MESSAGE));
    } finally {
      this.isSubmitting.set(false);
    }
  }

  async toggleActive(member: CompanyMember) {
    if (this.isSubmitting()) return;
    const activate = !member.is_active;
    const name = `${member.names ?? ''} ${member.lastname ?? ''}`.trim() || member.email;
    const question = activate
      ? `¿Reactivar el acceso de ${name} a esta empresa?`
      : `¿Desactivar el acceso de ${name} a esta empresa? Podrás reactivarlo después. Su cuenta y su acceso a otras empresas no cambian.`;
    if (!confirm(question)) return;

    this.isSubmitting.set(true);
    this.successMessage.set(null);
    this.errorMessage.set(null);
    try {
      const outcome = interpretAccessResponse(await lastValueFrom(this.adminService.setMemberActive(member.email, activate)));
      if (!outcome.ok) {
        this.errorMessage.set(outcome.message);
        return;
      }
      const accountNote = activate && outcome.data.account_is_active === false
        ? ' Su cuenta está desactivada a nivel global (WhatsApp y Chat Web); contacta a soporte para reactivarla.'
        : '';
      this.successMessage.set((activate ? 'Acceso reactivado.' : 'Acceso desactivado.') + accountNote);
      this.adminService.loadMembers();
    } catch (error) {
      this.errorMessage.set(gatewayErrorMessage(error, NETWORK_ERROR_MESSAGE));
    } finally {
      this.isSubmitting.set(false);
    }
  }

  private emptyForm(): MemberFormData {
    return { email: '', names: '', lastname: '', phone: '', role: 'EDITOR', password: '' };
  }
}
