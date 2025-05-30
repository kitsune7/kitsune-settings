import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { z } from 'zod'
import { $ } from 'zx'

const server = new McpServer({
  name: 'kitsune-mcp',
  version: '1.0.0',
  capabilities: {
    resources: {},
    tools: {},
  },
})

// server.tool('test_tool', 'This is a test tool', {}, async () => {
//   const cwd = $.sync`pwd`.stdout.trim()

//   return {
//     content: [{ type: 'text', text: `The current working directory is ${cwd}.` }],
//   }
// })

server.tool(
  'commit_local_changes_for_pr',
  'Commit local changes to a new branch and open a page to create a PR',
  {
    git_repo_path: z.string(),
    new_branch_name: z.string(),
    commit_message: z.string(),
  },
  async (params) => {
    $.cwd = params.git_repo_path
    const defaultBranch = $.sync`git remote show origin | sed -n '/HEAD branch/s/.*: //p'`.stdout.trim()
    const currentBranch = $.sync`git branch --show-current`.stdout.trim()
    if (defaultBranch !== currentBranch) {
      return {
        content: [
          {
            type: 'text',
            text: `You are currently on branch ${currentBranch}, but the default branch is ${defaultBranch}. This tool expects you to be on the default branch.
            If you'd like to move forward anyway, just run \`pr ${params.new_branch_name} "${params.commit_message}"\` and then \`gh pr create --web\`.`,
          },
        ],
      }
    }

    await $`git checkout -b ${params.new_branch_name}`
    await $`git add .`
    // TODO: This seems to wrap everything in single quotes and prefix it with a $. This is not what we want.
    await $`git commit -m "${params.commit_message}"`
    await $`git push origin ${params.new_branch_name}`
    await $`gh pr create --web`

    return {
      content: [
        {
          type: 'text',
          text: `Created a new branch ${params.new_branch_name} and pushed the changes to it. A page has been opened in the browser to create a PR for it.`,
        },
      ],
    }
  },
)

server.tool(
  'commit_local_changes_for_pr_test',
  'Test commiting local changes to a new branch and opening a page to create a PR',
  {
    git_repo_path: z.string(),
    new_branch_name: z.string(),
    commit_message: z.string(),
  },
  async (params) => {
    $.cwd = params.git_repo_path
    let output = ''
    output += (await $`echo "git checkout -b ${params.new_branch_name}"`).stdout
    output += (await $`echo "git add ."`).stdout
    // TODO: This seems to wrap everything in single quotes and prefix it with a $. This is not what we want.
    output += (await $`echo "git commit -m \"${params.commit_message}\""`).stdout
    output += (await $`echo "git push origin ${params.new_branch_name}"`).stdout
    output += (await $`echo "gh pr create --web"`).stdout

    return {
      content: [
        {
          type: 'text',
          text: `Created a new branch ${params.new_branch_name} and pushed the changes to it. A page has been opened in the browser to create a PR for it. Here's the output of the commands:
          ${output}`,
        },
      ],
    }
  },
)

const transport = new StdioServerTransport()
await server.connect(transport)

console.log('Kitsune MCP server started')
