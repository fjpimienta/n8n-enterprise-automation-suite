import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';
import { MAX_CAMPAIGNS, MAX_LABEL_LENGTH, MIN_CAMPAIGNS, Campaign, CampaignError, DEFAULT_GAP_DAYS } from '../../utils/palpation-campaigns';
import { campaignErrorText } from '../../utils/palpation-campaign-view';

/**
 * Editor of the campaigns (user-defined inclusive date ranges, 2 to 6). Presentational: it receives the list and the validation errors and
 * emits the new list; the page owns the state. The ranges it shows at first are only a PROPOSAL (`suggested`): the user edits, adds or
 * removes them and can ask for a new proposal. Nothing is stored. Every control is a native form element, so it works with the keyboard.
 */
@Component({
  selector: 'app-palpation-campaigns-editor',
  standalone: true,
  templateUrl: './palpation-campaigns-editor.component.html',
  // The stock red text, red outline button and grey outline button are 3.2 to 3.4:1 on the dark theme. These set their own colours for both
  // themes (at least 4.5:1 on the real background). The meaning stays in the words of each message and button.
  styles: [
    `
      .palp-error {
        color: #b42323;
      }
      .palp-remove {
        color: #b42323;
        border-color: #b42323;
      }
      .palp-remove:hover:not(:disabled) {
        color: #ffffff;
        background-color: #b42323;
        border-color: #b42323;
      }
      .palp-suggest {
        color: #475569;
        border-color: #94a3b8;
      }
      .palp-suggest:hover {
        color: #ffffff;
        background-color: #475569;
        border-color: #475569;
      }
      :host-context([data-bs-theme='dark']) .palp-error {
        color: #ff9b9b;
      }
      :host-context([data-bs-theme='dark']) .palp-remove {
        color: #ff9b9b;
        border-color: #ff9b9b;
      }
      :host-context([data-bs-theme='dark']) .palp-remove:hover:not(:disabled) {
        color: #1d273b;
        background-color: #ff9b9b;
        border-color: #ff9b9b;
      }
      :host-context([data-bs-theme='dark']) .palp-suggest {
        color: #cfd8e3;
        border-color: #8696ab;
      }
      :host-context([data-bs-theme='dark']) .palp-suggest:hover {
        color: #ffffff;
        background-color: #4a5a70;
        border-color: #8696ab;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationCampaignsEditorComponent {
  readonly campaigns = input.required<readonly Campaign[]>();
  readonly errors = input<readonly CampaignError[]>([]);
  /** True while the list is still the automatic proposal (the user has not edited it). */
  readonly suggested = input<boolean>(false);

  readonly campaignsChange = output<Campaign[]>();
  /** The user asked for a new automatic proposal. */
  readonly resuggest = output<void>();

  protected readonly min = MIN_CAMPAIGNS;
  protected readonly max = MAX_CAMPAIGNS;
  protected readonly maxLabel = MAX_LABEL_LENGTH;
  protected readonly gap = DEFAULT_GAP_DAYS;

  protected readonly canAdd = computed(() => this.campaigns().length < MAX_CAMPAIGNS);
  /** A valid list never goes below the minimum by removing: with exactly 2 campaigns the remove buttons are disabled. */
  protected readonly canRemove = computed(() => this.campaigns().length !== MIN_CAMPAIGNS);
  protected readonly listErrors = computed(() => this.errors().filter(e => e.id === null).map(campaignErrorText));

  protected errorsOf(id: string): string[] {
    return this.errors().filter(e => e.id === id).map(campaignErrorText);
  }

  protected has(id: string, ...codes: CampaignError['code'][]): boolean {
    return this.errors().some(e => e.id === id && codes.includes(e.code));
  }

  protected add(): void {
    if (!this.canAdd()) return;
    const list = this.campaigns();
    const used = new Set(list.map(c => c.label.trim().toLowerCase()));
    let n = list.length + 1;
    while (used.has(`campaña ${n}`)) n += 1;
    const next = Math.max(0, ...list.map(c => Number(/^camp-(\d+)$/.exec(c.id)?.[1] ?? 0))) + 1;
    this.campaignsChange.emit([...list, { id: `camp-${next}`, label: `Campaña ${n}`, from: '', to: '' }]);
  }

  protected remove(id: string): void {
    if (!this.canRemove()) return;
    this.campaignsChange.emit(this.campaigns().filter(c => c.id !== id));
  }

  protected edit(id: string, field: 'label' | 'from' | 'to', event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.campaignsChange.emit(this.campaigns().map(c => (c.id === id ? { ...c, [field]: value } : c)));
  }
}
