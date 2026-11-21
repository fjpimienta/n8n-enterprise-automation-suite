import { NgOptimizedImage } from '@angular/common';
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { PROFILE } from '../data/profile';
import { SITE, whatsappLink } from '../core/site.config';

@Component({
  selector: 'app-profile',
  imports: [NgOptimizedImage],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './profile.html',
})
export class Profile {
  readonly profile = PROFILE;
  readonly site = SITE;
  readonly whatsappHref = whatsappLink('Hola, quiero hablar con Francisco.');
}
