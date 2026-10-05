import { exportRowsToCsv } from './csv-export.util';

describe('exportRowsToCsv', () => {
  interface Row { name: string; note: string }

  function captureBlobText(): { getText: () => Promise<string>; restore: () => void } {
    const originalCreate = URL.createObjectURL;
    const originalRevoke = URL.revokeObjectURL;
    let capturedBlob: Blob | null = null;

    URL.createObjectURL = ((blob: Blob) => {
      capturedBlob = blob;
      return 'blob:mock';
    }) as typeof URL.createObjectURL;
    URL.revokeObjectURL = (() => {}) as typeof URL.revokeObjectURL;

    return {
      getText: () => capturedBlob!.text(),
      restore: () => {
        URL.createObjectURL = originalCreate;
        URL.revokeObjectURL = originalRevoke;
      }
    };
  }

  it('builds a header row plus one row per input, quoting every cell', async () => {
    const { getText, restore } = captureBlobText();
    try {
      const rows: Row[] = [{ name: 'Ana', note: 'ok' }, { name: 'Beto', note: 'ok' }];
      exportRowsToCsv(rows, [
        { header: 'Nombre', value: r => r.name },
        { header: 'Nota', value: r => r.note }
      ], 'test.csv');

      const text = (await getText()).replace(/^﻿/, '');
      expect(text).toBe('"Nombre","Nota"\n"Ana","ok"\n"Beto","ok"');
    } finally {
      restore();
    }
  });

  it('escapes embedded quotes and handles empty/undefined values', async () => {
    const { getText, restore } = captureBlobText();
    try {
      const rows: Row[] = [{ name: 'Say "hi"', note: '' }];
      exportRowsToCsv(rows, [
        { header: 'Nombre', value: r => r.name },
        { header: 'Nota', value: r => r.note }
      ], 'test.csv');

      const text = (await getText()).replace(/^﻿/, '');
      expect(text).toBe('"Nombre","Nota"\n"Say ""hi""",""');
    } finally {
      restore();
    }
  });
});
