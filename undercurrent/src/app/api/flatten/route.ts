import { NextRequest } from "next/server";
import { streamFromEngine, abortEngine } from "@/lib/engine";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function sse(data: unknown): Uint8Array {
  return new TextEncoder().encode(`data: ${JSON.stringify(data)}\n\n`);
}

const IRON_SESSION_PROMPT = (treeContent: string) =>
  `You are given an original text/question and its root response, along with multiple exploration branches that users created by selecting text and drilling deeper.

Your job is to "iron" (熨烫) all the branch content back into the root response, producing a single, enriched, cohesive document that:
1. Preserves the structure and flow of the original root response
2. Weaves in the deeper explanations from branches at the appropriate places
3. Removes redundancy — don't repeat what the root already says
4. Maintains a consistent tone and reading level
5. Uses markdown formatting
6. If there are <user_note> tags, these are the user's own thoughts — incorporate them naturally as the author's voice, not as quoted material

Here is the tree content:

${treeContent}

Now produce the ironed/flattened document. Output ONLY the final enriched text in markdown, no meta-commentary.`;

const IRON_UP_PROMPT = (treeContent: string) =>
  `You are given a parent response and an exploration branch that a user created by selecting text and drilling deeper into it.

Your job is to "iron" (熨烫) the exploration content back into the parent response, producing a single, enriched, cohesive document that:
1. Preserves the structure and flow of the parent response
2. Weaves in the deeper explanations from the exploration at the appropriate place (near where the selected text appears)
3. If the exploration has its own sub-branches, incorporate those insights too
4. Removes redundancy — don't repeat what the parent already says
5. Maintains a consistent tone and reading level
6. Uses markdown formatting
7. If there are <user_note> tags, these are the user's own thoughts — incorporate them naturally as the author's voice

Here is the content:

${treeContent}

Now produce the enriched parent response with the exploration woven in. Output ONLY the final text in markdown, no meta-commentary.`;

export async function POST(req: NextRequest) {
  const { treeContent, nodeId, mode, instruction } = await req.json();

  let prompt =
    mode === "iron-up"
      ? IRON_UP_PROMPT(treeContent)
      : IRON_SESSION_PROMPT(treeContent);

  if (instruction) {
    prompt += `\n\nAdditional instructions from the user: ${instruction}`;
  }

  const stream = new ReadableStream({
    async start(controller) {
      controller.enqueue(sse({ type: "status", status: "spawning" }));
      try {
        let first = true;
        for await (const chunk of streamFromEngine("claude", prompt, nodeId)) {
          if (first) {
            controller.enqueue(sse({ type: "status", status: "thinking" }));
            first = false;
          }
          controller.enqueue(sse({ type: "chunk", text: chunk }));
        }
        controller.enqueue(sse({ type: "done" }));
      } catch (err) {
        const message = err instanceof Error ? err.message : "Unknown error";
        controller.enqueue(sse({ type: "error", message }));
      } finally {
        controller.close();
      }
    },
    cancel() {
      abortEngine(nodeId);
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
