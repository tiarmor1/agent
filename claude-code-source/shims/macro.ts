/**
 * Shim for MACRO build-time constants.
 * In production Bun builds, these are inlined at compile time.
 * Here we define them as a global object.
 */

declare global {
  const MACRO: {
    VERSION: string
    VERSION_CHANGELOG: string
    BUILD_TIME: string
    PACKAGE_URL: string
    NATIVE_PACKAGE_URL: string
    ISSUES_EXPLAINER: string
    FEEDBACK_CHANNEL: string
  }
}

;(globalThis as any).MACRO = {
  VERSION: '1.0.0-dev',
  VERSION_CHANGELOG: '',
  BUILD_TIME: new Date().toISOString(),
  PACKAGE_URL: 'https://github.com/anthropics/claude-code',
  NATIVE_PACKAGE_URL: 'https://github.com/anthropics/claude-code',
  ISSUES_EXPLAINER: 'report the issue at https://github.com/anthropics/claude-code/issues',
  FEEDBACK_CHANNEL: 'https://github.com/anthropics/claude-code/issues',
}

export {}
