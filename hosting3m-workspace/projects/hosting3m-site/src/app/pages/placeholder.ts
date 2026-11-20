import { Component, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';

@Component({
  selector: 'app-placeholder',
  template: `
    <section class="container-page py-16">
      <h1 class="text-3xl font-bold text-brand-900">{{ heading }}</h1>
      <p class="mt-4 text-muted">{{ todo }}</p>
    </section>
  `,
})
export class Placeholder {
  private readonly data = inject(ActivatedRoute).snapshot.data;
  readonly heading: string = this.data['heading'] ?? '';
  readonly todo: string = this.data['todo'] ?? '';
}
