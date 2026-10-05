/**
 * Client-side CSV export, same logic cattle-event-log.component.ts#exportCsv already has today
 * (UTF-8 BOM + quoted/escaped cells + Blob download), extracted so it can be reused without
 * duplicating it — cattle-event-log itself is meant to switch to calling this in its own
 * migration phase, not just new tables.
 */
export interface CsvColumn<T> {
  header: string;
  value: (row: T) => string;
}

export function exportRowsToCsv<T>(
  rows: readonly T[],
  columns: ReadonlyArray<CsvColumn<T>>,
  filename: string
): void {
  const header = columns.map(c => c.header);
  const lines = rows.map(row => columns.map(c => c.value(row)));

  const csv = [header, ...lines]
    .map(line => line.map(cell => `"${String(cell ?? '').replace(/"/g, '""')}"`).join(','))
    .join('\n');

  const blob = new Blob([`﻿${csv}`], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
