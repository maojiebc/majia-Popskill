@testable import Popskill
import Foundation
import Testing

struct SkillCLIClientTests {
    @Test
    func commandFailureMessageExtractsSidecarJsonError() {
        let stderr = """
        {
          "ok": false,
          "error": {
            "code": "COMMAND_FAILED",
            "message": "failed to install skill: network unavailable"
          }
        }
        """.data(using: .utf8)!

        let message = SkillCLIClient.commandFailureMessage(
            stdout: Data(),
            stderr: stderr,
            status: 1
        )

        #expect(message == "failed to install skill: network unavailable")
    }

    @Test
    func commandFailureMessageFallsBackToPlainText() {
        let message = SkillCLIClient.commandFailureMessage(
            stdout: Data(),
            stderr: Data("fatal: missing executable\n".utf8),
            status: 127
        )

        #expect(message == "fatal: missing executable")
    }

    @Test
    func commandFailureMessageFallsBackToExitStatus() {
        let message = SkillCLIClient.commandFailureMessage(
            stdout: Data(),
            stderr: Data(),
            status: 2
        )

        #expect(message == "skill-cli exited with 2")
    }

    @Test
    func cliErrorPayloadUsesServerMessageAsLocalizedDescription() {
        let error = CLIErrorPayload(code: "COMMAND_FAILED", message: "unsupported target app")

        #expect(error.localizedDescription == "unsupported target app")
    }
}
