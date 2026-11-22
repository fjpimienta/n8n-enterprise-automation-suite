import { IMAGE_LOADER, ImageLoaderConfig, NgOptimizedImage } from '@angular/common';
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { HERO } from '../data/home-copy';
import { whatsappLink } from '../core/site.config';

@Component({
  selector: 'app-hero',
  imports: [RouterLink, NgOptimizedImage],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './hero.html',
  // Static files, no CDN: map the requested width to the pre-built WebP variant (440 or 880 px wide).
  providers: [{ provide: IMAGE_LOADER, useValue: (config: ImageLoaderConfig) => `/images/hero-${config.width && config.width <= 440 ? 440 : 880}.webp` }],
})
export class Hero {
  readonly copy = HERO;
  readonly quoteHref = whatsappLink('Hola, quiero una cotización.');
}
