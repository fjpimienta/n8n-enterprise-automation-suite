import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { InlineSegment, parseInline } from '../../core/legal-text';
import { LEGAL_DOCS, LegalDoc } from '../../data/legal';

interface ViewBlock {
  readonly type: 'p' | 'ul' | 'table';
  readonly text?: readonly InlineSegment[];
  readonly items?: readonly (readonly InlineSegment[])[];
  readonly caption?: string;
  readonly columns?: readonly string[];
  readonly rows?: readonly (readonly (readonly InlineSegment[])[])[];
}
interface ViewSection {
  readonly id: string;
  readonly heading?: string;
  readonly blocks: readonly ViewBlock[];
}

/** Renders any LegalDoc (route data `legal`): one h1, h2 per section, lists and accessible tables. */
@Component({
  selector: 'app-legal-page',
  imports: [RouterLink, NgTemplateOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './legal-page.html',
})
export class LegalPage {
  private readonly doc: LegalDoc = LEGAL_DOCS[inject(ActivatedRoute).snapshot.data['legal'] as LegalDoc['slug']];
  readonly title = this.doc.title;
  readonly sections: readonly ViewSection[] = this.doc.sections.map((section, i) => ({
    id: `sec-${this.doc.slug}-${i}`,
    heading: section.heading,
    blocks: section.blocks.map((block): ViewBlock => {
      if (block.type === 'p') return { type: 'p', text: parseInline(block.text) };
      if (block.type === 'ul') return { type: 'ul', items: block.items.map(parseInline) };
      return { type: 'table', caption: block.caption, columns: block.columns, rows: block.rows.map((row) => row.map(parseInline)) };
    }),
  }));
}
