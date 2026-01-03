const { Blob } = require('buffer');

class File extends Blob {
  constructor(fileBits, fileName, options = {}) {
    super(fileBits, options);
    this.name = fileName.replace(/\//g, ":");
    this.lastModified = options.lastModified || Date.now();
  }
}

globalThis.Blob = Blob;
globalThis.File = File;
