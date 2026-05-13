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

    @Test
    func executableOverridePathTrimsAndExpandsTilde() {
        let path = SkillCLIClient.normalizedExecutableOverridePath(" ~/bin/skill-cli ")

        #expect(path == NSHomeDirectory() + "/bin/skill-cli")
        #expect(SkillCLIClient.normalizedExecutableOverridePath(" \n\t ") == nil)
    }

    @Test
    func webDAVConfigureInvocationPassesPasswordThroughEnvironment() {
        let invocation = SkillCLIClient.webDAVConfigureInvocation(for: WebDAVConfiguration(
            enabled: true,
            autoSync: false,
            baseUrl: "https://dav.example.com",
            username: "demo",
            password: "secret with spaces",
            remoteRoot: "cc-switch-sync",
            profile: "default"
        ))

        #expect(invocation.arguments.contains("--password-env"))
        #expect(!invocation.arguments.contains("secret with spaces"))
        #expect(invocation.environment?[SkillCLIClient.webDAVPasswordEnvironmentKey] == "secret with spaces")
    }

    @Test
    func webDAVConfigureInvocationOmitsPasswordEnvironmentWhenBlank() {
        let invocation = SkillCLIClient.webDAVConfigureInvocation(for: WebDAVConfiguration(
            enabled: false,
            autoSync: true,
            baseUrl: "https://dav.example.com",
            username: "demo",
            password: "",
            remoteRoot: "team-sync",
            profile: "work"
        ))

        #expect(!invocation.arguments.contains("--password-env"))
        #expect(invocation.environment == nil)
        #expect(invocation.arguments.contains("team-sync"))
        #expect(invocation.arguments.contains("work"))
    }
}
