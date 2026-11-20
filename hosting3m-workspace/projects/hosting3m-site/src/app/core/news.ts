import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { timeout } from 'rxjs';
import { RUNTIME } from './runtime-config';
import fallback from '../data/news-fallback.json';

export interface NewsItem {
  readonly title: string;
  readonly url: string;
  readonly source: string;
  readonly image: string | null;
  readonly publishedAt: Date | null;
  readonly summary: string;
}

const MAX_ITEMS = 6;

/** Returns the normalized URL only for http(s); everything else (javascript:, data:, ...) is rejected. */
export function safeHttpUrl(value: unknown, httpsOnly = false): string | null {
  if (typeof value !== 'string' || value.length === 0 || value.length > 2048) return null;
  try {
    const url = new URL(value);
    const ok = url.protocol === 'https:' || (!httpsOnly && url.protocol === 'http:');
    return ok ? url.toString() : null;
  } catch {
    return null;
  }
}

/** Validates the untrusted API response. Output is only ever rendered through Angular bindings. */
export function sanitizeNews(raw: unknown): NewsItem[] {
  if (!Array.isArray(raw)) return [];
  const items: NewsItem[] = [];
  for (const entry of raw) {
    if (items.length >= MAX_ITEMS) break;
    if (typeof entry !== 'object' || entry === null) continue;
    const e = entry as Record<string, unknown>;
    const title = typeof e['title'] === 'string' ? e['title'].trim().slice(0, 160) : '';
    const url = safeHttpUrl(e['url']);
    if (!title || !url) continue; // an empty collection may arrive as [{}]: skip anything without title and url
    const published = typeof e['published_at'] === 'string' ? new Date(e['published_at']) : null;
    items.push({
      title,
      url,
      source: typeof e['source'] === 'string' ? e['source'].trim().slice(0, 60) : '',
      image: safeHttpUrl(e['image'], true),
      publishedAt: published && !Number.isNaN(published.getTime()) ? published : null,
      summary: '',
    });
  }
  return items;
}

/** Own content (reviewed by the owner), shown when the API returns [] or fails. */
export const FALLBACK_NEWS: readonly NewsItem[] = fallback.map((n) => ({
  title: n.title,
  url: n.url,
  source: n.source,
  image: null,
  publishedAt: null,
  summary: n.summary,
}));

@Injectable({ providedIn: 'root' })
export class NewsService {
  private readonly http = inject(HttpClient);
  readonly items = signal<readonly NewsItem[]>(FALLBACK_NEWS);
  readonly isLive = signal(false);

  /** Browser only. Keeps the fallback on any error or empty answer. */
  load(): void {
    if (RUNTIME.mockApi) return;
    this.http
      .post<unknown>(`${RUNTIME.apiBase}/v6/news`, {})
      .pipe(timeout(8000))
      .subscribe({
        next: (res) => {
          const live = sanitizeNews(res);
          if (live.length > 0) {
            this.items.set(live);
            this.isLive.set(true);
          }
        },
        error: () => undefined,
      });
  }
}
