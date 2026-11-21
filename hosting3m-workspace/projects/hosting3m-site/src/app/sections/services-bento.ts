import { ChangeDetectionStrategy, Component } from '@angular/core';
import { SERVICES_SECTION } from '../data/home-copy';
import { SITE } from '../core/site.config';
import { Icon } from './icon';

@Component({
  selector: 'app-services-bento',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './services-bento.html',
})
export class ServicesBento {
  readonly copy = SERVICES_SECTION;
  readonly githubUrl = SITE.githubSuiteUrl;
}
