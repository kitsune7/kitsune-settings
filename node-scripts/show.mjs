import fs from 'fs/promises'
import path from 'path'

const directory = process.argv?.[2]

const reset = '\x1b[0m'
const fgBlack = '\x1b[30m'
const fgRed = '\x1b[31m'
const fgGreen = '\x1b[32m'
const fgYellow = '\x1b[33m'
const fgBlue = '\x1b[34m'
const fgMagenta = '\x1b[35m'
const fgCyan = '\x1b[36m'
const fgWhite = '\x1b[37m'
const fgGray = '\x1b[90m'

async function readCommands(filePath) {
  const content = await fs.readFile(filePath, 'utf-8')
  const lines = content.split('\n')
  const commands = []

  for (const line of lines) {
    const trimmedLine = line.trim()
    if (trimmedLine.startsWith('alias')) {
      const parts = trimmedLine.split('=')
      commands.push(parts[0].split(' ')[1]) // Extract alias name
    } else if (trimmedLine.startsWith('function')) {
      const parts = trimmedLine.split(' ')
      commands.push(parts[1]) // Extract function name
    }
  }

  return commands
}

async function processFile(filePath) {
  if (filePath.endsWith('.zsh')) {
    const filename = path.basename(filePath)
    const commands = await readCommands(filePath)

    if (commands.length) {
      console.log(fgCyan, filename, reset)
      commands.forEach((alias) => console.log(`  ${fgYellow}${alias}${reset}`))
    }
  }
}

;(async () => {
  try {
    if (!directory) {
      throw new Error('Target directory not provided as a command-line argument for the script')
    }
    const files = await fs.readdir(directory)
    for (const file of files) {
      const filePath = path.join(directory, file)
      await processFile(filePath)
    }
  } catch (error) {
    console.error(error)
  }
})()
