import { Component, inject, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterModule } from '@angular/router';
import { ComplianceService } from '../../services/compliance.service';

@Component({
  selector: 'app-upp-detail',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './upp-detail.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class UppDetailComponent implements OnInit {
  private route = inject(ActivatedRoute);
  public complianceService = inject(ComplianceService);

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id');
    if (id) {
      this.complianceService.getUppDetail(id);
    }
  }
}
