import { Component, inject } from '@angular/core';
import { ThreeStateService } from '../../../services/three-state';

@Component({
  selector: 'app-unit-sidebar',
  standalone: true,
  templateUrl: './unit-sidebar.component.html',
  styleUrls: ['./unit-sidebar.component.css']
})
export class UnitSidebarComponent {
  public threeState = inject(ThreeStateService);

  public changeFloor(floorName: string): void {
    this.threeState.setFloor(floorName);
  }

  public toggleXRay(): void {
    this.threeState.toggleXRay();
  }
}