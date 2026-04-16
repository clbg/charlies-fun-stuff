import { execSync } from "child_process";
import { detectBackend } from "@/lib/engine";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function hasCommand(cmd: string): boolean {
  try {
    execSync(`which ${cmd}`, { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

export async function GET() {
  const backend = await detectBackend();
  return Response.json({
    claude: hasCommand("claude") || backend === "bedrock",
    backend, // "bedrock" or "cli"
  });
}
