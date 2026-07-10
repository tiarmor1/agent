/**
 * Register CJS extension handlers for .txt and .md files.
 * Bun handles these natively, but Node.js CJS require() does not.
 * This preload runs via --import before any application code.
 */
import { readFileSync } from 'fs'
import { createRequire } from 'module'

// Access the CJS Module internals to register extension handlers
const require = createRequire(import.meta.url)
const Module = require('module')

// .txt → return file content as string (Bun's text loader behavior)
Module._extensions['.txt'] = function (mod, filename) {
  const content = readFileSync(filename, 'utf8')
  mod.exports = content
}

// .md → same behavior
Module._extensions['.md'] = function (mod, filename) {
  const content = readFileSync(filename, 'utf8')
  mod.exports = content
}
