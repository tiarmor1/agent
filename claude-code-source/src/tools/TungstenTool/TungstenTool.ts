// @ts-nocheck
/**
 * Stub for internal-only TungstenTool (requires USER_TYPE=ant).
 */
import { z } from 'zod/v4'
import { buildTool } from '../../Tool.js'

export const TungstenTool = buildTool({
  name: 'Tungsten',
  description: 'Internal tool (stub)',
  inputSchema: z.object({}),
  isEnabled: () => false,
  async *call() {
    yield { type: 'result' as const, resultForAssistant: 'Not available', resultForHuman: 'Not available' }
  },
})
