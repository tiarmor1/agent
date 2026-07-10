/**
 * Bootstrap entry point for running claude-code-source with tsx.
 * Loads shims (MACRO globals, bun:bundle mock) before the real entry point.
 */

// 0. Register tsx/cjs so that require() calls can load .ts/.tsx files.
import 'tsx/cjs'

import { createRequire } from 'module'
import { pathToFileURL } from 'url'
import { resolve as pathResolve } from 'path'

const projectRoot = pathResolve(
  new URL('.', import.meta.url).pathname,
)

const rootRequire = createRequire(
  pathToFileURL(pathResolve(projectRoot, 'package.json')).href,
)
const srcRequire = createRequire(
  pathToFileURL(pathResolve(projectRoot, 'src', '_virtual.js')).href,
)

/**
 * Try to require a specifier with .js → .ts/.tsx fallback.
 */
function tryRequire(req: NodeJS.Require, specifier: string): any {
  try { return req(specifier) } catch {}
  if (specifier.endsWith('.js')) {
    try { return req(specifier.replace(/\.js$/, '.ts')) } catch {}
    try { return req(specifier.replace(/\.js$/, '.tsx')) } catch {}
  }
  return undefined
}

// Install global require with Bun-compatible resolution
const globalRequire = function require(specifier: string): any {
  // Handle src/ prefixed paths (absolute imports used in Bun builds)
  if (specifier.startsWith('src/')) {
    const absPath = pathResolve(projectRoot, specifier)
    const result = tryRequire(rootRequire, absPath)
    if (result !== undefined) return result
    throw new Error(`Cannot find module '${specifier}'`)
  }

  // npm packages and node: builtins
  if (!specifier.startsWith('.') && !specifier.startsWith('/')) {
    if (specifier === 'modifiers-napi') {
      return rootRequire(pathResolve(projectRoot, 'shims/modifiers-napi.ts'))
    }
    return rootRequire(specifier)
  }

  // Relative paths: try from src/ first, then project root
  let result = tryRequire(srcRequire, specifier)
  if (result !== undefined) return result

  result = tryRequire(rootRequire, specifier)
  if (result !== undefined) return result

  throw new Error(`Cannot find module '${specifier}'`)
} as any

globalRequire.resolve = rootRequire.resolve
;(globalThis as any).require = globalRequire

// 1. Install MACRO globals
import './shims/macro.js'

// 2. Launch the CLI
import('./src/entrypoints/cli.js').catch((err) => {
  console.error('Failed to start:', err)
  process.exit(1)
})
