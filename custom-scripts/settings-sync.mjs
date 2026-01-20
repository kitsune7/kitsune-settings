import fs, { access, mkdir, readFile } from 'node:fs/promises'
import { join, isAbsolute, dirname } from 'node:path'
import { spawn } from 'node:child_process'

const CONFIG_PATH = process.env.SETTINGS_DIR
  ? join(process.env.SETTINGS_DIR, 'settings-sync.yaml')
  : null

main().catch((error) => {
  console.error(error.message ?? error)
  process.exit(1)
})

async function main() {
  const action = process.argv[2]
  const target = process.argv[3]

  if (!action || action === '-h' || action === '--help') {
    printUsage()
    process.exit(0)
  }

  const config = await loadConfig()
  const entries = normalizeEntries(config)

  if (action === 'list') {
    listEntries(entries)
    return
  }

  const isAll = target === '--all'
  const filteredEntries = isAll
    ? entries
    : entries.filter((entry) => entry.name === target)

  if (!filteredEntries.length) {
    throw new Error(`No entries matched "${target}". Try "list" to see available entries.`)
  }

  for (const entry of filteredEntries) {
    await handleEntry(action, entry)
  }
}

function printUsage() {
  console.log('Usage:')
  console.log('  settings-sync.mjs list')
  console.log('  settings-sync.mjs sync <name>|--all')
  console.log('  settings-sync.mjs push <name>|--all')
  console.log('  settings-sync.mjs pull <name>|--all')
}

async function loadConfig() {
  if (!CONFIG_PATH) {
    throw new Error('KITSUNE_SETTINGS is not set; cannot locate settings-sync.yml')
  }
  const contents = await readFile(CONFIG_PATH, 'utf-8')
  return parseSimpleYaml(contents)
}

function parseSimpleYaml(text) {
  const TAB_SIZE = 2
  const config = { defaults: {}, entries: [] }
  let section = null
  let currentEntry = null

  const lines = text.split(/\r?\n/)
  for (const rawLine of lines) {
    const line = stripInlineComment(rawLine)
    if (!line.trim()) continue

    const indent = line.match(/^ */)?.[0].length ?? 0
    if (indent === 0) {
      const parsed = parseKeyValue(line)
      if (!parsed) continue
      if (parsed.key === 'defaults') {
        section = 'defaults'
      } else if (parsed.key === 'entries') {
        section = 'entries'
      }
      currentEntry = null
      continue
    }

    if (section === 'defaults' && indent === 2) {
      const parsed = parseKeyValue(line.trim())
      if (parsed) {
        config.defaults[parsed.key] = parsed.value
      }
      continue
    }

    if (section === 'entries') {
      const trimmed = line.trim()
      if (indent === TAB_SIZE && trimmed.startsWith('- ')) {
        currentEntry = {}
        config.entries.push(currentEntry)
        const parsed = parseKeyValue(trimmed.slice(2))
        if (parsed) {
          currentEntry[parsed.key] = parsed.value
        }
        continue
      }
      if (indent === 2 * TAB_SIZE && currentEntry) {
        const parsed = parseKeyValue(trimmed)
        if (parsed) {
          currentEntry[parsed.key] = parsed.value
        }
      }
    }
  }

  return config
}

function stripInlineComment(line) {
  return line.replace(/\s+#.*$/, '')
}

function parseKeyValue(line) {
  const index = line.indexOf(':')
  if (index === -1) return null
  const key = line.slice(0, index).trim()
  let value = line.slice(index + 1).trim()
  if (!value) return { key, value: '' }
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    value = value.slice(1, -1)
  }
  return { key, value }
}

function normalizeEntries(config) {
  if (!CONFIG_PATH) {
    throw new Error('KITSUNE_SETTINGS is required to resolve the config path.')
  }

  const defaults = {
    local_root: config.defaults?.local_root ?? '$HOME',
    repo_root:
      config.defaults?.repo_root ??
      `${process.env.KITSUNE_SETTINGS ?? ''}/settings`
  }

  const localRoot = expandEnv(defaults.local_root)
  const repoRoot = expandEnv(defaults.repo_root)

  return (config.entries ?? []).map((entry) => {
    const localPath = resolveWithRoot(entry.local_path, localRoot)
    const repoPath = resolveWithRoot(entry.repo_path, repoRoot)
    return {
      ...entry,
      localPath,
      repoPath,
      _defaults: defaults,
    }
  })
}

function expandEnv(value) {
  if (!value) return value
  let expanded = value

  if (expanded.startsWith('~')) {
    expanded = expanded.replace(/^~(?=$|\/)/, process.env.HOME ?? '~')
  }

  expanded = expanded.replace(/\$([A-Z0-9_]+)/g, (_, name) => process.env[name] ?? `$${name}`)
  expanded = expanded.replace(/\$\{([A-Z0-9_]+)\}/g, (_, name) => process.env[name] ?? `\${${name}}`)

  return expanded
}

function resolveWithRoot(path, root) {
  const expanded = expandEnv(path)
  if (isAbsolute(expanded)) return expanded
  return join(root, expanded)
}

function listEntries(entries) {
  for (const entry of entries) {
    console.log(`${entry.name}`)
    console.log(`  description: ${entry.description}`)
    console.log(`  local: ${entry.localPath}`)
    console.log(`  repo:  ${entry.repoPath}`)
  }
}

async function handleEntry(action, entry) {
  const pathType = await resolvePathType(entry)
  if (action === 'push') {
    if (pathType === 'dir') {
      await rsyncDir(entry.localPath, entry.repoPath)
    } else {
      await rsyncFile(entry.localPath, entry.repoPath)
    }
    return
  }
  if (action === 'pull') {
    if (pathType === 'dir') {
      await rsyncDir(entry.repoPath, entry.localPath)
    } else {
      await rsyncFile(entry.repoPath, entry.localPath)
    }
    return
  }

  if (pathType === 'dir') {
    await syncDir(entry.localPath, entry.repoPath)
  } else {
    await syncFile(entry, entry.localPath, entry.repoPath)
  }
}

async function resolvePathType(entry) {
  if (await pathExists(entry.localPath)) {
    const stat = await fs.stat(entry.localPath)
    return stat.isDirectory() ? 'dir' : 'file'
  }
  if (await pathExists(entry.repoPath)) {
    const stat = await fs.stat(entry.repoPath)
    return stat.isDirectory() ? 'dir' : 'file'
  }
  if (entry.localPath.endsWith('/')) return 'dir'
  if (basename(entry.localPath).includes('.')) return 'file'

  // Assume directory if we can't determine the type
  console.warn(`Cannot determine path type for ${entry.name}; assuming directory`)
  return 'dir'
}

async function pathExists(path) {
  try {
    await access(path)
    return true
  } catch {
    return false
  }
}

async function rsyncDir(source, destination, options = {}) {
  await mkdir(destination, { recursive: true })
  const args = ['-a', '--progress']
  if (options.updateOnly) args.push('--update')
  args.push(`${source.replace(/\/$/, '')}/`, destination)
  await runRsync(args)
}

async function runRsync(args) {
  await new Promise((resolve, reject) => {
    const child = spawn('rsync', args, { stdio: 'inherit' })
    child.on('close', (code) => {
      if (code === 0) resolve()
      else reject(new Error(`rsync failed with exit code ${code}`))
    })
    child.on('error', reject)
  })
}

async function rsyncFile(source, destination) {
  await ensureParentDir(destination)
  await runRsync(['-a', '--progress', source, destination])
}

async function ensureParentDir(destination) {
  const dir = dirname(destination)
  try {
    await mkdir(dir, { recursive: true })
  } catch (error) {
    throw error
  }
}

async function syncDir(localPath, repoPath) {
  await rsyncDir(localPath, repoPath, { updateOnly: true })
  await rsyncDir(repoPath, localPath, { updateOnly: true })
}

async function syncFile(entry, localPath, repoPath) {
  const localExists = await pathExists(localPath)
  const repoExists = await pathExists(repoPath)

  if (!localExists && !repoExists) return

  if (!localExists) {
    await rsyncFile(repoPath, localPath)
    return
  }

  if (!repoExists) {
    await rsyncFile(localPath, repoPath)
    return
  }

  const [localStat, repoStat] = await Promise.all([fs.stat(localPath), fs.stat(repoPath)])
  if (localStat.mtimeMs > repoStat.mtimeMs) {
    await rsyncFile(localPath, repoPath)
  } else if (repoStat.mtimeMs > localStat.mtimeMs) {
    await rsyncFile(repoPath, localPath)
  } else if ((entry.default_source ?? entry._defaults.default_source) === 'repo') {
    await rsyncFile(repoPath, localPath)
  } else {
    await rsyncFile(localPath, repoPath)
  }
}


