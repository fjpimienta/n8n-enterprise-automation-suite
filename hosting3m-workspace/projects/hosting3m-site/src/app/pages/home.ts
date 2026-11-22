import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ContactSection } from '../sections/contact-section';
import { Hero } from '../sections/hero';
import { PlansSection } from '../sections/plans-section';
import { ServicePicker } from '../sections/service-picker';
import { ServicesBento } from '../sections/services-bento';
import { StepsFaq } from '../sections/steps-faq';
import { SystemsDemo } from '../sections/systems-demo';

/**
 * Home page, section by section (backgrounds alternate dark/light):
 * 1 hero (dark) · 2 Elige (light) · 3 servicios (dark) · 4 sistemas (light) · 5 Compara (dark) ·
 * 6 Así de simple + FAQ + noticias (light) · 7 Cotiza (dark) · 8 footer (light, in the app shell).
 */
@Component({
  selector: 'app-home',
  imports: [Hero, ServicePicker, ServicesBento, SystemsDemo, PlansSection, StepsFaq, ContactSection],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './home.html',
})
export class Home {}
