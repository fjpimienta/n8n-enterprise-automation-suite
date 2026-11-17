import { Component, inject, computed, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { ComplianceService, ComplianceFailure } from '../../services/compliance.service';

/**
 * - loading: at least one source has not finished (idle or in flight). Never green.
 * - unknown: both sources failed. Never green.
 * - partial: one source failed, the other loaded. Shows the working source's counts. Never green.
 * - attention: both loaded and at least one item needs attention.
 * - allclear: both loaded and nothing needs attention. The only green state.
 */
export type ComplianceVerdict = 'loading' | 'unknown' | 'partial' | 'attention' | 'allclear';

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

  public uppFailed = computed(() => this.complianceService.uppState() === 'failed');
  public psgFailed = computed(() => this.complianceService.psgState() === 'failed');

  public verdict = computed<ComplianceVerdict>(() => {
    const uppState = this.complianceService.uppState();
    const psgState = this.complianceService.psgState();
    if (uppState === 'idle' || uppState === 'loading' || psgState === 'idle' || psgState === 'loading') {
      return 'loading';
    }
    if (this.uppFailed() && this.psgFailed()) return 'unknown';
    if (this.uppFailed() || this.psgFailed()) return 'partial';
    return this.totalAttentionCount() > 0 ? 'attention' : 'allclear';
  });

  /** True when every failing source failed because the network was unavailable. */
  public networkFailure = computed(() => {
    const failures: ComplianceFailure[] = [this.complianceService.uppError(), this.complianceService.psgError()]
      .filter((f): f is ComplianceFailure => f !== null);
    return failures.length > 0 && failures.every(f => f.reason === 'network');
  });

  public failedLabel = computed(() => {
    if (this.uppFailed() && this.psgFailed()) return 'las UPP ni las licencias PSG';
    return this.uppFailed() ? 'las UPP' : 'las licencias PSG';
  });

  /** Counts only the sources that loaded, so a failed source never reads as "0 UPP". */
  public attentionTitle = computed(() => {
    const parts: string[] = [];
    if (!this.uppFailed()) {
      const upp = this.complianceService.expiredUppCount() + this.complianceService.warningUppCount();
      if (upp > 0) parts.push(`${upp} UPP requieren atención normativa`);
    }
    if (!this.psgFailed()) {
      const psg = this.complianceService.expiredPsgCount();
      if (psg > 0) parts.push(`${psg} PSG vencidas`);
    }
    return parts.join(' · ');
  });

  ngOnInit(): void {
    // Idempotent in the service: won't re-fetch if UppComplianceListComponent already loaded it.
    this.complianceService.loadUppStatus();
    this.complianceService.loadPsgStatus();
  }

  public retry(): void {
    this.complianceService.retryFailed();
  }
}
