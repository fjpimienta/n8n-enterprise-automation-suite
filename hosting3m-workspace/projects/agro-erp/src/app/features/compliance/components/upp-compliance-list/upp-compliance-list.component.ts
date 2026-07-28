import { Component, inject, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { ComplianceService } from '../../services/compliance.service';

@Component({
  selector: 'app-upp-compliance-list',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './upp-compliance-list.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class UppComplianceListComponent implements OnInit {
  public complianceService = inject(ComplianceService);

  ngOnInit(): void {
    this.complianceService.loadUppStatus();
  }
}
