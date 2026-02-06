import { Component, EventEmitter, Output, inject, input } from '@angular/core'; // <--- 1. Importa 'inject'
import { ThemeService } from '@core/services/theme.service'; // <--- 2. Importa tu servicio (ajusta la ruta si es necesario)

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [], // Asegúrate de importar lo necesario si usas standalone
  templateUrl: './header.component.html',
  styleUrl: './header.component.css'
})
export class HeaderComponent {
  // ... tus Outputs existentes ...
  @Output() onRefresh = new EventEmitter<void>();
  @Output() onRefreshMain = new EventEmitter<void>();
  @Output() onGenerateReport = new EventEmitter<void>();
  @Output() onLogout = new EventEmitter<void>();
  
  isAdmin = input.required<boolean>();

  // ✅ 3. INYECTA EL SERVICIO AQUÍ
  // Debe ser 'public' para que el HTML pueda verlo
  public themeService = inject(ThemeService);

}