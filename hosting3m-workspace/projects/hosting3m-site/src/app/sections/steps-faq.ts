import { ChangeDetectionStrategy, Component } from '@angular/core';
import { FAQ } from '../data/faq';
import { FAQ_SECTION, NEWS_SECTION, STEPS_SECTION, WHY_SECTION } from '../data/home-copy';
import { NewsSection } from './news-section';

/** Section 6 (light): "Así de simple", "Por qué Hosting3M", FAQ and the news cards (kept from the previous site). */
@Component({
  selector: 'app-steps-faq',
  imports: [NewsSection],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './steps-faq.html',
})
export class StepsFaq {
  readonly steps = STEPS_SECTION;
  readonly why = WHY_SECTION;
  readonly faqTitle = FAQ_SECTION.title;
  readonly faq = FAQ;
  readonly newsTitle = NEWS_SECTION.title;
}
