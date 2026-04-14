#!/usr/bin/env node
/**
 * Discord Channel — MCP stdio server + Discord.js hybrid module
 *
 * Message flow:
 *   Discord msg → mcp.notification("notifications/claude/channel") → Claude Code
 *   Claude reply tool → channel.send() → Discord
 */
import 'dotenv/config'
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js'
import { Client, GatewayIntentBits, Partials } from 'discord.js'
import fs from 'fs/promises'
import path from 'path'
import os from 'os'
import https from 'https'
import http from 'http'
import { z } from 'zod'

/**
 * @param {Object} config
 * @param {string} config.agentName
 * @param {string} config.homeChannel  — Discord channel ID (listen without mention)
 * @param {string} config.emoji
 * @param {string} config.instructions — MCP server instructions string
 */
export async function createChannel(config) {
  const { agentName, homeChannel, emoji, instructions } = config

  const DISCORD_BOT_TOKEN = process.env.DISCORD_BOT_TOKEN
  if (!DISCORD_BOT_TOKEN) {
    process.stderr.write(`[${agentName.toUpperCase()}] ERROR: DISCORD_BOT_TOKEN required\n`)
    process.exit(1)
  }

  const LABEL = agentName.toUpperCase()
  const log = (...args) => process.stderr.write(`[${LABEL}] ${args.join(' ')}\n`)

  const MEMORY_BASE = process.env.LULU_MEMORY_DIR
    ? process.env.LULU_MEMORY_DIR.replace(/^~/, os.homedir())
    : path.join(os.homedir(), 'Documents', 'Lulu_Memory')
  const INBOX_DIR = path.join(MEMORY_BASE, 'inbox')

  // Dedup guard
  const _processed = new Set()
  function isDuplicate(key) {
    if (_processed.has(key)) return true
    _processed.add(key)
    if (_processed.size > 2000) _processed.delete(_processed.values().next().value)
    return false
  }

  // Pending reactions
  const _pendingReactions = new Map()

  // ── Discord Client ──────────────────────────────────────────────────────
  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.DirectMessages,
      GatewayIntentBits.MessageContent,
    ],
    partials: [Partials.Channel, Partials.Message],
  })

  // ── Utilities ─────────────────────────────────────────────────────────
  function downloadBuffer(url, maxBytes = 20 * 1024 * 1024, depth = 0) {
    if (depth > 5) return Promise.reject(new Error('too many redirects'))
    return new Promise((resolve, reject) => {
      const proto = url.startsWith('https') ? https : http
      proto.get(url, { timeout: 15_000 }, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302)
          return downloadBuffer(res.headers.location, maxBytes, depth + 1).then(resolve, reject)
        if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode}`)) }
        const chunks = []; let len = 0
        res.on('data', c => { len += c.length; if (len > maxBytes) { res.destroy(); reject(new Error('too large')) } else chunks.push(c) })
        res.on('end', () => resolve(Buffer.concat(chunks)))
        res.on('error', reject)
      }).on('error', reject)
    })
  }

  const IMAGE_EXTS = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp'])
  const DOC_EXTS = new Set(['.pdf', '.json', '.csv', '.xlsx', '.docx', '.pptx', '.txt', '.md'])

  async function downloadFileLocal(url, name) {
    try {
      const buf = await downloadBuffer(url)
      await fs.mkdir(INBOX_DIR, { recursive: true })
      const safeName = `${Date.now()}_${path.basename(name).replace(/[^a-zA-Z0-9._-]/g, '_')}`
      const dest = path.join(INBOX_DIR, safeName)
      await fs.writeFile(dest, buf)
      return dest
    } catch (e) { log('File download failed:', e.message); return null }
  }

  // ── MCP Server ────────────────────────────────────────────────────────
  const mcp = new Server(
    { name: agentName, version: '1.0.0' },
    {
      capabilities: {
        experimental: { 'claude/channel': {}, 'claude/channel/permission': {} },
        tools: {},
      },
      instructions,
    },
  )

  let _lastChannelId = homeChannel || ''

  const tools = [
    {
      name: 'reply',
      description: 'Send a message to a Discord channel.',
      inputSchema: {
        type: 'object',
        properties: {
          channelId: { type: 'string', description: 'Discord channel ID' },
          text: { type: 'string', description: 'Message content (markdown supported)' },
          replyToMessageId: { type: 'string', description: 'Message ID to reply to (optional)' },
        },
        required: ['channelId', 'text'],
      },
    },
    {
      name: 'send_file_to_discord',
      description: 'Upload a local file to a Discord channel.',
      inputSchema: {
        type: 'object',
        properties: {
          file_path: { type: 'string', description: 'Full local file path' },
          channel_id: { type: 'string', description: 'Channel ID. Defaults to current channel.' },
          comment: { type: 'string', description: 'Optional message with the upload' },
        },
        required: ['file_path'],
      },
    },
    {
      name: 'dismiss',
      description: 'Dismiss thinking reaction without sending a reply.',
      inputSchema: { type: 'object', properties: {}, required: [] },
    },
    {
      name: 'restart',
      description: 'Restart the agent process.',
      inputSchema: { type: 'object', properties: { reason: { type: 'string' } }, required: [] },
    },
  ]

  mcp.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }))

  mcp.setRequestHandler(CallToolRequestSchema, async (req) => {
    const { name, arguments: args } = req.params
    const toolArgs = args || {}

    if (name === 'reply') {
      const { channelId, text, replyToMessageId } = toolArgs
      _lastChannelId = channelId
      try {
        const channel = await client.channels.fetch(channelId)
        // Discord message limit: 2000 chars
        const chunks = []
        for (let i = 0; i < text.length; i += 1900) chunks.push(text.slice(i, i + 1900))

        for (let i = 0; i < chunks.length; i++) {
          const content = `${emoji} **[${LABEL}]**\n${chunks[i]}`
          if (i === 0 && replyToMessageId) {
            try {
              const targetMsg = await channel.messages.fetch(replyToMessageId)
              await targetMsg.reply({ content })
            } catch {
              await channel.send({ content })
            }
          } else {
            await channel.send({ content })
          }
        }

        // Remove thinking reactions
        for (const [chId, msgs] of _pendingReactions) {
          for (const msgId of msgs) {
            try {
              const ch = await client.channels.fetch(chId)
              const msg = await ch.messages.fetch(msgId)
              await msg.reactions.cache.get('\u{1F914}')?.users.remove(client.user.id)
            } catch {}
          }
        }
        _pendingReactions.clear()

        return { content: [{ type: 'text', text: 'sent' }] }
      } catch (e) {
        return { content: [{ type: 'text', text: `send error: ${e.message}` }] }
      }
    }

    if (name === 'send_file_to_discord') {
      const filePath = toolArgs.file_path?.startsWith('~')
        ? toolArgs.file_path.replace('~', os.homedir())
        : toolArgs.file_path
      const channelId = toolArgs.channel_id || _lastChannelId
      if (!channelId) return { content: [{ type: 'text', text: 'channelId missing' }] }
      try {
        const channel = await client.channels.fetch(channelId)
        await channel.send({
          content: toolArgs.comment ? `${emoji} **[${LABEL}]** ${toolArgs.comment}` : undefined,
          files: [filePath],
        })
        return { content: [{ type: 'text', text: `File sent: ${path.basename(filePath)}` }] }
      } catch (e) {
        return { content: [{ type: 'text', text: `File send failed: ${e.message}` }] }
      }
    }

    if (name === 'dismiss') {
      for (const [chId, msgs] of _pendingReactions) {
        for (const msgId of msgs) {
          try {
            const ch = await client.channels.fetch(chId)
            const msg = await ch.messages.fetch(msgId)
            await msg.reactions.cache.get('\u{1F914}')?.users.remove(client.user.id)
          } catch {}
        }
      }
      _pendingReactions.clear()
      return { content: [{ type: 'text', text: 'dismissed' }] }
    }

    if (name === 'restart') {
      log(`Restart requested: ${toolArgs.reason || 'no reason'}`)
      setTimeout(() => {
        try { process.kill(process.ppid, 'SIGTERM') } catch {}
        process.exit(0)
      }, 500)
      return { content: [{ type: 'text', text: 'restarting...' }] }
    }

    throw new Error(`unknown tool: ${name}`)
  })

  // ── Permission auto-approve ──────────────────────────────────────────
  const PermissionSchema = z.object({
    method: z.literal('notifications/claude/channel/permission_request'),
    params: z.object({ request_id: z.string(), tool_name: z.string(), description: z.string(), input_preview: z.string() }),
  })
  mcp.setNotificationHandler(PermissionSchema, async ({ params }) => {
    log(`Auto-approve: ${params.tool_name} [${params.request_id}]`)
    mcp.notification({
      method: 'notifications/claude/channel/permission',
      params: { request_id: params.request_id, behavior: 'allow' },
    }).catch(() => {})
  })

  // ── Message handler ──────────────────────────────────────────────────
  client.on('messageCreate', async (message) => {
    if (message.author.bot) return
    if (isDuplicate(`${agentName}_${message.id}`)) return

    const isDM = !message.guild
    const isMentioned = message.mentions.has(client.user)
    const isHomeChannel = message.channel.id === homeChannel

    if (!isDM && !isMentioned && !isHomeChannel) return

    let msgText = message.content.replace(/<@!?\d+>/g, '').trim().slice(0, 4000)
    const username = message.author.displayName || message.author.username

    // Handle attachments
    for (const att of message.attachments.values()) {
      const ext = path.extname(att.name || '').toLowerCase()
      if (IMAGE_EXTS.has(ext) || DOC_EXTS.has(ext)) {
        const localPath = await downloadFileLocal(att.url, att.name)
        if (localPath) {
          msgText += `\n[File: ${att.name} — use Read tool to inspect]\n${localPath}`
        }
      } else {
        msgText += `\n[Attachment: ${att.name} (${att.url})]`
      }
    }

    // Reply context
    let replyCtx = ''
    if (message.reference?.messageId) {
      try {
        const refMsg = await message.channel.messages.fetch(message.reference.messageId)
        const refUser = refMsg.author.displayName || refMsg.author.username
        const refText = refMsg.content.replace(/<@!?\d+>/g, '').trim().slice(0, 1000)
        replyCtx = `[Reply to]\n${refUser}: ${refText}\n[End reply]\n\n`
      } catch {}
    }

    _lastChannelId = message.channel.id

    // Add thinking reaction
    try {
      await message.react('\u{1F914}')
      if (!_pendingReactions.has(message.channel.id)) _pendingReactions.set(message.channel.id, new Set())
      _pendingReactions.get(message.channel.id).add(message.id)
    } catch {}

    mcp.notification({
      method: 'notifications/claude/channel',
      params: {
        content: `${replyCtx}${msgText}`,
        meta: {
          sender: username,
          authorId: message.author.id,
          channelId: message.channel.id,
          messageId: message.id,
          timestamp: new Date().toISOString(),
        },
      },
    }).catch(e => log('notification failed:', e.message))

    log(`Message from ${username} | ch:${message.channel.id} | ${msgText.slice(0, 80)}...`)
  })

  // ── Session note reminder (30 min) ──────────────────────────────────
  const SESSION_NOTE_INTERVAL = parseInt(process.env.SESSION_NOTE_INTERVAL_MS, 10) || 30 * 60 * 1000
  setInterval(() => {
    mcp.notification({
      method: 'notifications/claude/channel',
      params: {
        content: `[SYSTEM] 30 minutes elapsed. Write session notes to ~/Documents/Lulu_Memory/session_notes/lulu/ (today's date file). Append if exists.`,
        meta: { sender: 'SYSTEM', channelId: '', authorId: '', timestamp: new Date().toISOString() },
      },
    }).catch(() => {})
  }, SESSION_NOTE_INTERVAL)

  // ── Start ─────────────────────────────────────────────────────────────
  await mcp.connect(new StdioServerTransport())
  log('MCP server started')
  await client.login(DISCORD_BOT_TOKEN)
  log(`Discord connected as ${client.user.tag}`)

  return { mcp, client }
}
