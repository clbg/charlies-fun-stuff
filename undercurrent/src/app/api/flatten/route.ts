import { NextRequest } from "next/server";
import { streamFromEngine, abortEngine } from "@/lib/engine";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function sse(data: unknown): Uint8Array {
  return new TextEncoder().encode(`data: ${JSON.stringify(data)}\n\n`);
}

export async function POST(req: NextRequest) {
  const { treeContent, nodeId } = await req.json();

  const prompt = `You are given an original text/question and its root response, along with multiple exploration branches that users created by selecting text and drilling deeper.

Your job is to "iron" (熨烫) all the branch content back into the root response, producing a single, enriched, cohesive document that:
1. Preserves the structure and flow of the original root response
2. Weaves in the deeper explanations from branches at the appropriate places
3. Removes redundancy — don't repeat what the root already says
4. Maintains a consistent tone and reading level
5. Uses markdown formatting

Here is the tree content:

${treeContent}

Now produce the ironed/flattened document. Output ONLY the final enriched text in markdown, no meta-commentary.`;

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
