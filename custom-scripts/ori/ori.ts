#!/usr/bin/env bun

import express from 'express';
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

const app = express();
app.use(express.json());

// Add CORS headers middleware
app.use((_, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'PUT, POST, PATCH, DELETE, GET');
  res.header('Access-Control-Allow-Headers', '*');
  next();
});

app.all('*', (req, _, next) => {
  console.debug(`Received request: ${req.method} to ${req.url} with body`, req.body);
  next();
});

// Handle OPTIONS requests
app.options('/v1/chat/completions', (req, res) => {
  res.json({});
});

app.post('/v1/chat/completions', async (req, res) => {
  try {
    if (!await checkLmStudioStatus()) {
      await startLmStudio();
      await loadModel();
    }

    console.info(`Running chat completion on conversation with ${req.body.messages.length} message${req.body.messages.length > 1 ? 's' : ''}.`);

    const toolSchemas = await loadToolSchemas();
    const response = await fetch(`${LM_STUDIO_URL}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...req.body, tools: toolSchemas }),
    });

    const content = await response.json() as LMStudioResponse;

    if (response.ok && content.choices?.[0]?.message?.tool_calls) {
      for (const toolCall of content.choices[0].message.tool_calls) {
        content.choices[0].finish_reason = 'stop';
        
        const toolName = toolCall.function.name;
        const toolArgs = JSON.parse(toolCall.function.arguments);
        const toolResult = await executeTool(toolName, toolArgs);

        if (toolResult.error) {
          return res.status(500).json({
            error: toolResult.error,
            choices: [{
              message: {
                content: toolResult.error,
                role: 'assistant',
              }
            }]
          });
        }

        content.tool_results = toolResult.content;
        content.choices[0].message = {
          content: toolResult.content,
          role: 'assistant',
        };
      }
    }

    res.json(content);
  } catch (error: any) {
    console.error(`Error processing request: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

const port = 1230;
const server = app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
server.keepAliveTimeout = 5 * 1000;
