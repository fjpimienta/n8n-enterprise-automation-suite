import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-room-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-card.component.html',
  styleUrl: './room-card.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class RoomCardComponent {
  room = input.required<any>();
  onSelect = output<any>();
  onReportIssue = output<void>();
}
