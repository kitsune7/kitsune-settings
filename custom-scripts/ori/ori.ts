#!/usr/bin/env bun

import { spawn } from 'child_process';
import { promises as fs } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

interface ToolResult {
  error: string;
  content: string;
}

interface CreateNoteArgs {
  note_name?: string;
  note_content?: string;
}

interface LMStudioResponse {
  choices: Array<{
    message: {
      content?: string;
      role: string;
      tool_calls?: Array<{
        function: {
          name: string;
          arguments: string;
        };
      }>;
    };
    finish_reason?: string;
  }>;
  tool_results?: string;
  error?: string;
}

const LM_STUDIO_URL = 'http://localhost:1234/v1';

// Load tool schemas
const loadToolSchemas = async () => {
  const scriptDir = dirname(fileURLToPath(import.meta.url));
  const toolsDir = join(scriptDir, 'tools');
  const files = await fs.readdir(toolsDir);
  const schemas = await Promise.all(
    files.map(file => fs.readFile(join(toolsDir, file)).then((text) => JSON.parse(text.toString())))
  );
  return schemas;
};

const startLmStudio = (): Promise<void> => {
  return new Promise((resolve, reject) => {
    const process = spawn('lms', ['server', 'start'], { shell: true });
    process.on('close', (code: number) => {
      if (code === 0) {
        console.log('LM Studio server started successfully');
        resolve();
      } else {
        console.error('Failed to start LM Studio server');
        reject(new Error('Failed to start LM Studio server'));
      }
    });
  });
};

const loadModel = (): Promise<void> => {
  return new Promise((resolve, reject) => {
    const process = spawn('lms', ['model', 'load', '--first'], { shell: true });
    process.on('close', (code: number) => {
      if (code === 0) {
        console.log('Model loaded successfully');
        resolve();
      } else {
        console.error('Failed to load model');
        reject(new Error('Failed to load model'));
      }
    });
  });
};

const checkLmStudioStatus = async (): Promise<boolean> => {
  try {
    const response = await fetch(`${LM_STUDIO_URL}/models`);
    return response.status === 200;
  } catch (error) {
    return false;
  }
};

const createNote = async (toolArgs: CreateNoteArgs): Promise<ToolResult> => {
  const workNotesPath = process.env.ICLOUD_WORK_NOTES_DIR;
  const intermediatePath = '5 - Unsorted';
  
  if (!workNotesPath) {
    return {
      error: 'ICLOUD_WORK_NOTES_DIR environment variable is not set',
      content: '',
    };
  }

  const noteName = toolArgs.note_name || 'Untitled Ori Note';
  const noteContent = toolArgs.note_content || '';
  const notePath = join(workNotesPath, intermediatePath, `${noteName}.md`);

  try {
    await fs.writeFile(notePath, noteContent);
    return {
      error: '',
      content: `Created note successfully: ${intermediatePath}/${noteName}.md`,
    };
  } catch (error: any) {
    return {
      error: `Failed to create note: ${error.message}`,
      content: '',
    };
  }
};

const executeTool = async (toolName: string, toolArgs: any): Promise<ToolResult> => {
  const toolNameToFunction: { [key: string]: (args: any) => Promise<ToolResult> } = {
    'create_note': createNote,
  };

  if (toolName in toolNameToFunction) {
    return await toolNameToFunction[toolName](toolArgs);
  }
  return { error: `Unknown tool: ${toolName}`, content: '' };
};

const server = Bun.serve({
  port: 1230,
  async fetch(req) {
    try {
      if (req.method !== 'POST') {
        return new Response('Method not allowed', { status: 405 });
      }

      if (!await checkLmStudioStatus()) {
        await startLmStudio();
        await loadModel();
      }

      const toolSchemas = await loadToolSchemas();
      const body = await req.json() as Record<string, unknown>;
      
      const response = await fetch(`${LM_STUDIO_URL}${new URL(req.url).pathname}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...body, tools: toolSchemas }),
      });

      const content = await response.json() as LMStudioResponse;

      if (response.ok && content.choices?.[0]?.message?.tool_calls) {
        for (const toolCall of content.choices[0].message.tool_calls) {
          content.choices[0].finish_reason = 'stop';
          
          const toolName = toolCall.function.name;
          const toolArgs = JSON.parse(toolCall.function.arguments);
          const toolResult = await executeTool(toolName, toolArgs);

          if (toolResult.error) {
            return Response.json({
              error: toolResult.error,
              choices: [{
                message: {
                  content: toolResult.error,
                  role: 'assistant',
                }
              }]
            }, { status: 500 });
          }

          content.tool_results = toolResult.content;
          content.choices[0].message = {
            content: toolResult.content,
            role: 'assistant',
          };
        }
      }

      return Response.json(content);
    } catch (error: any) {
      return Response.json({ error: error.message }, { status: 500 });
    }
  },
});

console.log(`Server running on port ${server.port}`);
