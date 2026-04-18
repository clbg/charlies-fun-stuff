import type { ContextEntry } from "./types";

/**
 * Build the prompt sent to the CLI engine.
 */
export function buildPrompt(
  context: ContextEntry[],
  selection: string,
  question?: string
): string {
  const parts: string[] = [];

  for (const entry of context) {
    switch (entry.role) {
      case "root":
        parts.push(`<original_content>\n${entry.text}\n</original_content>`);
        break;
      case "selection-trail":
        parts.push(
          `<exploration_path>\nThe user has been exploring: ${entry.text}\n</exploration_path>`
        );
        break;
      case "parent":
        parts.push(
          `<parent_context>\n${entry.text}\n</parent_context>`
        );
        break;
    }
  }

  parts.push(`<selected_text>\n${selection}\n</selected_text>`);

  if (question) {
    parts.push(
      `The user selected the text above and asks: "${question}"\n\nProvide a clear, focused answer. Use markdown formatting. Do not repeat what was already explained in the parent context.`
    );
  } else {
    parts.push(
      `The user selected the text above and wants to understand it more deeply.\n\nProvide a clear, focused explanation that goes deeper into this specific concept. Use markdown formatting. Do not repeat what was already explained in the parent context.`
    );
  }

  return parts.join("\n\n");
}
