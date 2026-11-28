import { ChangeDetectionStrategy, Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule } from '@angular/forms';
import { LoginComponent } from '@features/admin/components/login/login.component';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';

/** `next` login: new template over the unchanged classic form logic (two-step company selection included). */
@Component({
  selector: 'app-login-next',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './login-next.component.html'
})
export class LoginNextComponent extends LoginComponent {}
