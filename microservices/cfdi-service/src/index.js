import path from 'node:path';
import { createApp } from './app.js';

const token = process.env.CFDI_SERVICE_TOKEN;
const storageRoot = process.env.STORAGE_ROOT;

if (!token) {
  console.error('CFDI_SERVICE_TOKEN is not set; refusing to start');
  process.exit(1);
}
if (!storageRoot || !path.isAbsolute(storageRoot)) {
  console.error('STORAGE_ROOT must be set to an absolute path; refusing to start');
  process.exit(1);
}

const port = Number(process.env.PORT) || 4100;
createApp({ token, storageRoot }).listen(port, '0.0.0.0', () => console.log(JSON.stringify({ msg: 'cfdi-service listening', port })));
