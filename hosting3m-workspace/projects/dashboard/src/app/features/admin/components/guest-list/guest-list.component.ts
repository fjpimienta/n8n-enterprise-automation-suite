import { CommonModule } from '@angular/common';
import { Component, input, output } from '@angular/core';

@Component({
  selector: 'app-guest-list',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './guest-list.component.html',
  styleUrl: './guest-list.component.css',
})
export class GuestListComponent {
  guests = input.required<any[]>();

  onBack = output<void>();
  onAdd = output<void>();
  onEdit = output<any>();
}
