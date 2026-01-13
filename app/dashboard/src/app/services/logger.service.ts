import { Injectable, isDevMode } from '@angular/core';

@Injectable({
  providedIn: 'root'
})
export class LoggerService {
  // isDevMode() es una función nativa de Angular que detecta si estás en desarrollo
  private isDevelopment = isDevMode();

  log(msg: any, ...optionalParams: any[]) {
    if (this.isDevelopment) {
      console.log(`[LOG]:`, msg, ...optionalParams);
    }
  }

  error(msg: any, ...optionalParams: any[]) {
    if (this.isDevelopment) {
      console.error(`[ERROR]:`, msg, ...optionalParams);
    }
  }

  warn(msg: any, ...optionalParams: any[]) {
    if (this.isDevelopment) {
      console.warn(`[WARN]:`, msg, ...optionalParams);
    }
  }
}