import fs from 'fs/promises'
import { type } from 'os'
import path from 'path'

const directory = process.argv?.[2]
const commandFilter = process.argv?.[3]

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
      commands.push({
        type: 'alias',
        name: parts[0].split(' ')[1],
        definition: trimmedLine,
      })
    } else if (trimmedLine.startsWith('function')) {
      const parts = trimmedLine.split(' ')
      commands.push({
        type: 'function',
        name: parts[1],
        definition: extractBashFunction(parts[1], content),
      })
    }
  }

  return commands
}

function extractBashFunction(functionName, fileContents) {
  const pattern = new RegExp(`function\\s+${functionName}\\s*\\([^)]*\\)\\s*\\{.*?\\n\\}`, 'gms')
  const match = pattern.exec(fileContents)
  if (!match) return null
  return match[0]
}

function outputCommandsForFile(filePath, commands) {
  if (commands.length) {
    console.log(fgCyan, path.basename(filePath), reset)
    commands.forEach((command) =>
      console.log(`  ${command.type === 'alias' ? fgYellow : fgMagenta}${command.name}${reset}`),
    )
  }
}

;(async () => {
  try {
    if (!directory) {
      throw new Error('Target directory not provided as a command-line argument for the script')
    }
    const files = (await fs.readdir(directory)).filter((file) => file.endsWith('.zsh'))
    for (const file of files) {
      const filePath = path.join(directory, file)
      const commands = await readCommands(filePath)

      if (commandFilter) {
        const command = commands.find((command) => command.name === commandFilter)
        if (command) {
          console.log(command.definition)
          break
        }
      } else {
        outputCommandsForFile(filePath, commands)
      }
    }
  } catch (error) {
    console.error(error)
  }
})()
