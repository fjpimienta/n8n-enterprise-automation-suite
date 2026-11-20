import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, afterNextRender, inject } from '@angular/core';
import { NewsService } from '../core/news';

@Component({
  selector: 'app-news-section',
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ul class="grid gap-6 md:grid-cols-3">
      @for (item of news.items(); track item.url + item.title) {
        <li class="flex flex-col overflow-hidden rounded-xl border border-slate-200 bg-white">
          @if (item.image) {
            <img [src]="item.image" alt="" width="640" height="360" loading="lazy" decoding="async"
              referrerpolicy="no-referrer" class="aspect-video w-full object-cover" />
          }
          <div class="flex flex-1 flex-col p-5">
            <h3 class="text-lg font-semibold">
              <a [href]="item.url" target="_blank" rel="noopener noreferrer" class="hover:underline">{{ item.title }}</a>
            </h3>
            @if (item.summary) { <p class="mt-2 text-muted">{{ item.summary }}</p> }
            <p class="mt-auto pt-4 text-sm text-muted">
              {{ item.source }}@if (item.publishedAt) { · <time [attr.datetime]="item.publishedAt.toISOString()">{{ item.publishedAt | date: 'd MMM y' : 'UTC' : 'es-MX' }}</time> }
            </p>
          </div>
        </li>
      }
    </ul>
  `,
})
export class NewsSection {
  readonly news = inject(NewsService);

  constructor() {
    afterNextRender(() => this.news.load());
  }
}
