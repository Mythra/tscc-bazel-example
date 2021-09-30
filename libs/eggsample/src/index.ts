/** @define {string} set by the compiler to list the version */
const BUILD_VERSION = '<unknown>';

function TOTALLY_UNREFERENCED(): void { console.log('begone foul beast'); }

function LOG_NOT_KEPT(): void {
  console.log('Hello from not kept');
}

function LNK(): void {
  console.log(BUILD_VERSION);
  LOG_NOT_KEPT();
  const a = 10;
  const b = 20;
  const c = a + b;
  console.log(c);
}