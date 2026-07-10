/**
 * Custom Node.js ESM loader that intercepts:
 * - bun:bundle → shims/bun-bundle.ts
 * - bun:ffi → shims/bun-ffi.ts
 * - color-diff-napi → src/native-ts/color-diff/index.ts
 * - @anthropic-ai/claude-agent-sdk → shims/claude-agent-sdk.ts
 * - src/* absolute imports → resolved file paths
 * - .md/.txt files → text modules
 * - .d.ts files → empty modules
 * - Injects require() shim for ESM files (Bun compat)
 */

import { resolve as pathResolve } from 'path'
import { pathToFileURL, fileURLToPath } from 'url'
import { existsSync, readFileSync } from 'fs'

const ROOT = pathResolve(fileURLToPath(import.meta.url), '../..')

export function resolve(specifier, context, nextResolve) {
  // Intercept bun:bundle
  if (specifier === 'bun:bundle') {
    return {
      url: pathToFileURL(pathResolve(ROOT, 'shims/bun-bundle.ts')).href,
      shortCircuit: true,
    }
  }

  // Intercept bun:ffi
  if (specifier === 'bun:ffi') {
    return {
      url: pathToFileURL(pathResolve(ROOT, 'shims/bun-ffi.ts')).href,
      shortCircuit: true,
    }
  }

  // Intercept color-diff-napi
  if (specifier === 'color-diff-napi') {
    return {
      url: pathToFileURL(pathResolve(ROOT, 'src/native-ts/color-diff/index.ts')).href,
      shortCircuit: true,
    }
  }

  // Intercept modifiers-napi (native module, not available outside Bun)
  if (specifier === 'modifiers-napi') {
    return {
      url: pathToFileURL(pathResolve(ROOT, 'shims/modifiers-napi.ts')).href,
      shortCircuit: true,
    }
  }

  // Intercept @anthropic-ai/claude-agent-sdk
  if (specifier === '@anthropic-ai/claude-agent-sdk') {
    return {
      url: pathToFileURL(pathResolve(ROOT, 'shims/claude-agent-sdk.ts')).href,
      shortCircuit: true,
    }
  }

  // Intercept src/* absolute imports (used throughout the codebase)
  if (specifier.startsWith('src/')) {
    const resolved = pathResolve(ROOT, specifier)
    // Try .ts extension if original ends with .js
    const tsPath = resolved.replace(/\.js$/, '.ts')
    const tsxPath = resolved.replace(/\.js$/, '.tsx')

    if (existsSync(tsPath)) {
      return { url: pathToFileURL(tsPath).href, shortCircuit: true }
    }
    if (existsSync(tsxPath)) {
      return { url: pathToFileURL(tsxPath).href, shortCircuit: true }
    }
    if (existsSync(resolved)) {
      return { url: pathToFileURL(resolved).href, shortCircuit: true }
    }
    // Fallback: let tsx handle it
    return { url: pathToFileURL(resolved).href, shortCircuit: true }
  }

  return nextResolve(specifier, context)
}

/**
 * Custom load hook to handle special file types and inject require() shim.
 * Bun provides require() in ESM context; Node.js does not.
 * We inject createRequire so that require() calls in the deobfuscated source work.
 */
export async function load(url, context, nextLoad) {
  // Handle .d.ts files as empty modules (type-only)
  if (url.endsWith('.d.ts')) {
    return {
      format: 'module',
      source: 'export {};\n',
      shortCircuit: true,
    }
  }

  // Handle .txt files as text modules (Bun's text loader)
  if (url.endsWith('.txt')) {
    const filePath = fileURLToPath(url)
    const content = readFileSync(filePath, 'utf8')
    return {
      format: 'module',
      source: `export default ${JSON.stringify(content)};\n`,
      shortCircuit: true,
    }
  }

  if (url.endsWith('.md')) {
    const filePath = fileURLToPath(url)
    const content = readFileSync(filePath, 'utf8')
    return {
      format: 'module',
      source: `export default ${JSON.stringify(content)};\n`,
      shortCircuit: true,
    }
  }

  // Let tsx (or default loader) process the file first
  const result = await nextLoad(url, context)

  // Inject require() shim for ESM files that use require() —
  // Bun provides require() natively in ESM; Node.js does not.
  // Only inject for project source files (not node_modules).
  if (
    result.format === 'module' &&
    result.source &&
    url.startsWith('file://') &&
    !url.includes('/node_modules/')
  ) {
    let source = typeof result.source === 'string'
      ? result.source
      : result.source.toString()

    if (source.includes('require(') && !source.includes('createRequire')) {
      source =
        `import { createRequire as __cjsRequire } from 'module';\n` +
        `const require = __cjsRequire(import.meta.url);\n` +
        source
      return { ...result, source, shortCircuit: true }
    }
  }

  return result
}
