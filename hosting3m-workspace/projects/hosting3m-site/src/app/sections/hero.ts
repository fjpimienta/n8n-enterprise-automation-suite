import { NgOptimizedImage } from '@angular/common';
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { HERO } from '../data/home-copy';
import { whatsappLink } from '../core/site.config';

@Component({
  selector: 'app-hero',
  imports: [RouterLink, NgOptimizedImage],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './hero.html',
})
export class Hero {
  readonly copy = HERO;
  readonly quoteHref = whatsappLink('Hola, quiero una cotización.');
}
