import { Pipe, PipeTransform } from '@angular/core';

@Pipe({ name: 'timeOnIce', standalone: true })
export class TimeOnIcePipe implements PipeTransform {
  transform(startTime: string): string {
    if (!startTime) return '00:00';
    
    const start = new Date();
    const [hrs, mins] = startTime.split(':');
    start.setHours(+hrs, +mins, 0);
    
    const diff = Math.floor((new Date().getTime() - start.getTime()) / 60000);
    return `${diff} min`;
  }
}