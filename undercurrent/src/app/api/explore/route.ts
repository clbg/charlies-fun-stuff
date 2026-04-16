import { NextRequest } from "next/server";
import { streamFromEngine, abortEngine } from "@/lib/engine";
import { buildPrompt } from "@/lib/prompt";
import type { ExploreRequest } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function sse(data: unknown): Uint8Array {
  return new TextEncoder().encode(`data: ${JSON.stringify(data)}\n\n`);
}

export async function POST(req: NextRequest) {
  const body: ExploreRequest & { nodeId: string } = await req.json();
  const { engine, context, selection, question, model, nodeId } = body;

  const prompt = buildPrompt(context, selection, question);

  const stream = new ReadableStream({
    async start(controller) {
      // Phase 1: spawning
      controller.enqueue(sse({ type: "status", status: "spawning" }));

      try {
        let firstChunk = true;
        for await (const chunk of streamFromEngine(engine, prompt, nodeId, { model })) {
          if (firstChunk) {
            // Phase 2→3: first data means we're now streaming
            controller.enqueue(sse({ type: "status", status: "thinking" }));
            firstChunk = false;
          }
          controller.enqueue(sse({ type: "chunk", text: chunk }));
        }
        controller.enqueue(sse({ type: "done" }));
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Unknown error";
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
