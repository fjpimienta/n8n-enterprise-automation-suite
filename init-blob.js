const { Blob } = require("buffer");

if (typeof Blob === 'undefined') {
  global.Blob = require('buffer').Blob;
}

if (typeof globalThis.Blob === "undefined") {
  globalThis.Blob = Blob;
}

if (typeof global.Blob === "undefined") {
  global.Blob = Blob;
}

if (typeof globalThis.File === "undefined") {
  globalThis.File = class File extends Blob {
    constructor(chunks, name, options = {}) {
      super(chunks, options);
      this.name = name;
      this.lastModified = options.lastModified || Date.now();
    }
  };
}

if (typeof global.File === "undefined") {
  global.File = globalThis.File;
}
