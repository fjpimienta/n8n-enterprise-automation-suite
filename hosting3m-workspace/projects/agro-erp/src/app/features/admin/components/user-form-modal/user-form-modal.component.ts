import { CommonModule } from '@angular/common';
import { Component, computed, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CompanyMember, MemberFormData } from '@core/models/company-member.model';
import { MEMBER_ROLE_OPTIONS, MIN_PASSWORD_LENGTH } from '@shared/utils/member-access.util';

@Component({
  selector: 'app-user-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './user-form-modal.component.html',
  styleUrl: './user-form-modal.component.css',
})
export class UserFormModalComponent {
  readonly roleOptions = MEMBER_ROLE_OPTIONS;
  readonly minPasswordLength = MIN_PASSWORD_LENGTH;

  isOpen = input.required<boolean>();
  selectedMember = input<CompanyMember | null>(null);
  userData = model.required<MemberFormData>();
  /** False when the person also belongs to another company: names/phone/password are read-only here. */
  profileEditable = input<boolean>(true);
  /** True when editing yourself: an ADMIN cannot change their own role. */
  roleLocked = input<boolean>(false);
  isSubmitting = input<boolean>(false);
  errorMessage = input<string | null>(null);

  onClose = output<void>();
  onSave = output<void>();

  selectedRoleDescription = computed(() =>
    this.roleOptions.find(o => o.value === this.userData().role)?.description ?? ''
  );

  updateField<K extends keyof MemberFormData>(key: K, value: MemberFormData[K]) {
    this.userData.update(current => ({ ...current, [key]: value }));
  }
}
