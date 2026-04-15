#!/usr/bin/env node
/**
 * Notion MCP wrapper — loads .env then spawns @notionhq/notion-mcp-server
 * with the correct OPENAPI_MCP_HEADERS env var.
 */
import 'dotenv/config'
import { spawn } from 'child_process'
import path from 'path'
import { fileURLToPath } from 'url'

const key = process.env.NOTION_API_KEY
if (!key || !key.trim()) {
  process.stderr.write('[NOTION] NOTION_API_KEY not set in .env — skipping\n')
  process.exit(0)
}

const headers = JSON.stringify({
  Authorization: `Bearer ${key.trim()}`,
  'Notion-Version': '2022-06-28',
})

const serverEntry = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  'node_modules/@notionhq/notion-mcp-server/bin/cli.mjs',
)

const child = spawn(process.execPath, [serverEntry], {
  env: { ...process.env, OPENAPI_MCP_HEADERS: headers },
  stdio: 'inherit',
})

child.on('exit', (code) => process.exit(code ?? 0))
