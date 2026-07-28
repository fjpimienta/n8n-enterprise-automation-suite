import { Component, inject, computed, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { ComplianceService } from '../../services/compliance.service';

@Component({
  selector: 'app-compliance-alert-card',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './compliance-alert-card.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class ComplianceAlertCardComponent implements OnInit {
  public complianceService = inject(ComplianceService);

  public totalAttentionCount = computed(() =>
    this.complianceService.expiredUppCount() +
    this.complianceService.warningUppCount() +
    this.complianceService.expiredPsgCount()
  );

  ngOnInit(): void {
    // Idempotent in the service: won't re-fetch if UppComplianceListComponent already loaded it.
    this.complianceService.loadUppStatus();
    this.complianceService.loadPsgStatus();
  }
}
