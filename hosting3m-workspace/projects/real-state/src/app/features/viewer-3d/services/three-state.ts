import { Injectable, signal } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class ThreeStateService {
  // --- SIGNALS (Para la UI rápida del HTML) ---
  public isModelLoading = signal<boolean>(false);
  public loadingProgress = signal<number>(0);
  public selectedUnitId = signal<number | null>(null);

  // --- RxJS SUBJECTS (Para lógica compleja y suscripciones) ---
  private currentFloor = new BehaviorSubject<string>('todos');
  public currentFloor$ = this.currentFloor.asObservable();

  private xrayMode = new BehaviorSubject<boolean>(false);
  public xrayMode$ = this.xrayMode.asObservable();

  // --- MÉTODOS DE MUTACIÓN ---
  public setLoading(isLoading: boolean): void {
    this.isModelLoading.set(isLoading);
  }

  public updateProgress(percent: number): void {
    this.loadingProgress.set(Math.round(percent));
  }

  public selectUnit(unitId: number | null): void {
    this.selectedUnitId.set(unitId);
  }

  public setFloor(floor: string): void {
    this.currentFloor.next(floor);
  }

  public toggleXRay(): void {
    this.xrayMode.next(!this.xrayMode.value);
  }
}