---
name: mastra
description: Mastra v1 API patterns and examples. Reference material for agents, tools, workflows, and streaming. Based on latest @mastra/core docs.
context: fork
user_invocable: true
---

# Mastra v1 API Reference

Quick reference for `@mastra/core` v1 patterns used in OpenNews. Online resources often show outdated v0 syntax — always use these patterns.

## Import Paths (Subpath Exports)

```typescript
import { Mastra } from '@mastra/core';           // Mastra instance + Config type
import { Agent } from '@mastra/core/agent';        // Agent class
import { createTool } from '@mastra/core/tools';   // Tool factory
import { createWorkflow, createStep } from '@mastra/core/workflows'; // Workflow API
```

**WRONG** (v0 / barrel import):
```typescript
// ❌ import { Mastra, Agent, createTool, Workflow } from '@mastra/core';
// ❌ import { Mastra } from '@mastra/core/mastra'; // removed in latest v1
```

## Agent

### Creation

```typescript
import { Agent } from '@mastra/core/agent';

export const myAgent = new Agent({
  id: 'my-agent',
  name: 'My Agent',
  instructions: 'You are a helpful assistant.',
  model: createModel('fast'),  // or string: 'openai/gpt-5.1'
  tools: { myTool },           // optional, object of tools
});
```

### Generate (Non-Streaming, Structured Output)

```typescript
import { z } from 'zod';

const outputSchema = z.object({
  summary: z.string(),
  tags: z.array(z.string()),
});

const result = await agent.generate(prompt, {
  structuredOutput: { schema: outputSchema },
});

const typed = result.object; // typed from Zod schema
```

### Stream

```typescript
const stream = await agent.stream(prompt, {
  onFinish: ({ steps, text, finishReason, usage }) => {
    console.log({ usage });
  },
});

// Option A: consume text stream
for await (const chunk of stream.textStream) {
  process.stdout.write(chunk);
}

// Option B: get full text after stream completes
const fullText = await stream.text;

// Option C: return as HTTP response (Hono/Express)
return stream.toDataStreamResponse();
```

### Stream with Structured Output

```typescript
const stream = await agent.stream(prompt, {
  structuredOutput: {
    schema: mySchema,
    errorStrategy: 'warn', // optional: 'throw' | 'warn'
  },
});

// Get typed result after stream completes
const result = await stream.object;

// Or consume partial objects as they stream
for await (const partial of stream.objectStream) {
  console.log(partial); // Partial<OutputType>
}
```

## Tool

### Creation

```typescript
import { createTool } from '@mastra/core/tools';
import { z } from 'zod';

export const myTool = createTool({
  id: 'my-tool',
  description: 'Does something useful',
  inputSchema: z.object({
    query: z.string().describe('Search query'),
    limit: z.number().default(5),
  }),
  outputSchema: z.object({
    results: z.array(z.object({ title: z.string(), url: z.string() })),
  }),
  execute: async (inputData, context) => {
    // inputData is typed from inputSchema
    // context is optional: { mastra?, requestContext?, writer? }
    const results = await search(inputData.query, inputData.limit);
    return { results };
  },
});
```

**v0 → v1 migration pitfall:**
```typescript
// ❌ v0: execute: async ({ context }) => { context.query }
// ✅ v1: execute: async (inputData, context) => { inputData.query }
```

## Workflow

### Creation with Chained Steps

```typescript
import { createWorkflow, createStep } from '@mastra/core/workflows';
import { z } from 'zod';

const step1 = createStep({
  id: 'fetch-data',
  inputSchema: z.object({ date: z.string() }),
  outputSchema: z.object({ items: z.array(z.string()) }),
  execute: async ({ inputData }) => {
    return { items: await fetchItems(inputData.date) };
  },
});

const step2 = createStep({
  id: 'process-data',
  inputSchema: z.object({ items: z.array(z.string()) }),
  outputSchema: z.object({ count: z.number() }),
  execute: async ({ inputData }) => {
    return { count: inputData.items.length };
  },
});

export const myWorkflow = createWorkflow({
  id: 'my-workflow',
  inputSchema: z.object({ date: z.string() }),
  outputSchema: z.object({ count: z.number() }),
})
  .then(step1)
  .then(step2)
  .commit();
```

**v0 → v1 migration pitfall:**
```typescript
// ❌ v0: new Workflow({ name: '...' }).step(new Step({ ... })).commit()
// ✅ v1: createWorkflow({ id: '...' }).then(createStep({ ... })).commit()
```

### Parallel Steps

```typescript
const workflow = createWorkflow({
  id: 'parallel-example',
  inputSchema: z.object({ message: z.string() }),
  outputSchema: z.object({ result: z.string() }),
})
  .parallel([step1, step2])  // executes in parallel
  .then(combineStep)          // receives { 'step1-id': output1, 'step2-id': output2 }
  .commit();
```

### Agent as Workflow Step

```typescript
const agentStep = createStep(myAgent, {
  structuredOutput: { schema: outputSchema },
});

const workflow = createWorkflow({ id: 'agent-workflow', inputSchema, outputSchema })
  .map(async ({ inputData }) => ({
    prompt: `Process: ${inputData.message}`,
  }))
  .then(agentStep)
  .then(processStep)
  .commit();
```

### Execution

```typescript
const run = await myWorkflow.createRun();
const result = await run.start({
  inputData: { date: '2026-02-08' },
});
```

## Mastra Instance

```typescript
import { Mastra } from '@mastra/core';

export const mastra = new Mastra({
  agents: {
    headlineGenerator: headlineAgent,
    articleGenerator: articleAgent,
  },
  workflows: {
    dailyDigest: dailyDigestWorkflow,
  },
});

// Retrieve by ID
const agent = mastra.getAgent('headlineGenerator');
const workflow = mastra.getWorkflow('dailyDigest');
```

## Hono Integration (Streaming Response)

```typescript
import { Hono } from 'hono';

const app = new Hono();

app.post('/api/v1/article/:topicId/generate', async (c) => {
  const agent = mastra.getAgent('articleGenerator');
  const stream = await agent.stream(prompt);
  return stream.toDataStreamResponse(); // Returns AI SDK-compatible SSE Response
});
```

## Common Mistakes to Avoid

| Mistake | Correct Pattern |
|---------|----------------|
| Import from `@mastra/core` barrel | Use subpath: `/agent`, `/tools`, `/workflows` |
| `new Workflow()` / `new Step()` | `createWorkflow()` / `createStep()` |
| `.step()` chaining | `.then()` chaining + `.commit()` |
| `execute({ context })` in tools | `execute(inputData, context)` |
| `response.object` after generate | `result.object` (the return IS the result) |
| `agent.run()` | `agent.generate()` or `agent.stream()` |
