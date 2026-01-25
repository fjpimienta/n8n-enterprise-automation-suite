import { Component, OnInit, inject } from '@angular/core'; // Añade importProvidersFrom
import { IceOperationsService } from '@features/operations/services/ice-operation';
import { TimeOnIcePipe } from '@shared/pipes/time-on-ice-pipe';
import { LucideAngularModule } from 'lucide-angular'; // Importa los iconos
import { SkeletonComponent } from '@shared/ui/loader/skeleton/skeleton.component';

@Component({
  selector: 'app-ice-monitor',
  standalone: true,
  imports: [
    LucideAngularModule,
    TimeOnIcePipe,
    SkeletonComponent
  ],
  templateUrl: './ice-monitor.html',
  styleUrls: ['./ice-monitor.css']
})
export class IceMonitorComponent implements OnInit {
  public iceService = inject(IceOperationsService);

  ngOnInit() {
    // El setTimeout previene el error NG0100 (ExpressionChangedAfterItHasBeenChecked)
    setTimeout(() => {
      this.refresh();
    }, 0);

    setInterval(() => this.refresh(), 30000);
  }

  refresh() {
    this.iceService.fetchActiveSkaters();
  }
}