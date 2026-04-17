import Foundation

/// CLI entry point for agent-operator.
///
/// This is currently a placeholder scaffold. Future subcommands will
/// communicate with the AgentOperatorApp (and eventually a remote
/// voice-bridge / Asterisk setup) to manage voice-telephone agent sessions.
@main
struct CLI {

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let subcommand = args.first else {
            printUsage()
            exit(1)
        }

        switch subcommand {
        case "hello":
            print("hello from agent-operator")
        case "-h", "--help", "help":
            printUsage()
        default:
            fputs("Unknown command: \(subcommand)\n", stderr)
            printUsage()
            exit(1)
        }
    }

    private static func printUsage() {
        let usage = """
        agent-operator — CLI for the AgentOperator menu-bar client

        USAGE:
            agent-operator <subcommand>

        SUBCOMMANDS:
            hello     Print a greeting (placeholder)
            help      Show this help message
        """
        print(usage)
    }
}
