import { Component, inject } from '@angular/core';
import { LayoutService } from '@shared/services/layout.service';

@Component({
  selector: 'app-header',
  standalone: true, // Asegurar que sea standalone
  imports: [],
  templateUrl: './header.component.html',
  styleUrl: './header.component.scss', // Mantener en singular
})
export class HeaderComponent {
  // Inyección de dependencias para controlar el menú móvil[cite: 9]
  public layoutService = inject(LayoutService);
}