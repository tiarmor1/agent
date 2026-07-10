/**
 * Stub for bun:ffi. Only used in upstreamproxy.ts for Linux prctl() calls.
 * Not needed when running outside Bun.
 */
export function dlopen() {
  throw new Error('bun:ffi is not available outside Bun runtime')
}

export function ptr() { return 0n }
export function toBuffer() { return Buffer.alloc(0) }
export function toArrayBuffer() { return new ArrayBuffer(0) }
export function CString() { return '' }

export const FFIType = {
  char: 0, i8: 1, i16: 2, i32: 3, i64: 4, i64_fast: 5,
  u8: 6, u16: 7, u32: 8, u64: 9, u64_fast: 10,
  f32: 11, f64: 12, bool: 13, ptr: 14, void: 15, cstring: 16,
}
