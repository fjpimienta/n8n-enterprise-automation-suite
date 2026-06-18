import { Component, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-palm-dashboard',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './palm-dashboard.component.html',
  styleUrls: ['./palm-dashboard.component.scss']
})
export class PalmDashboardComponent { }