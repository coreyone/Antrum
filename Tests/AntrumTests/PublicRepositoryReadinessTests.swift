import Foundation
import Testing
@testable import Antrum

@Suite("Public repository readiness")
struct PublicRepositoryReadinessTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test
    func requiredCommunityAndLicenseFilesExist() {
        let requiredPaths = [
            "LICENSE",
            "THIRD_PARTY_AND_MODEL_NOTICES.md",
            "CONTRIBUTING.md",
            "SECURITY.md",
            "SUPPORT.md",
            ".github/CODEOWNERS",
            ".github/pull_request_template.md",
            ".github/ISSUE_TEMPLATE/bug_report.yml",
            ".github/ISSUE_TEMPLATE/feature_request.yml",
            ".github/ISSUE_TEMPLATE/config.yml",
            ".github/workflows/ci.yml"
        ]

        for path in requiredPaths {
            #expect(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path))
        }
    }

    @Test
    func internalArtifactsAndWriteWorkflowsAreAbsent() {
        let excludedPaths = [
            "APP_STORE_SUBMISSION.md",
            "test.wav",
            "tasks/prd-antrum-current.md",
            ".github/workflows/ai-remediation.yml",
            ".github/workflows/auto-merge.yml",
            ".github/workflows/pr-controller.yml",
            ".github/workflows/release.yml",
            ".github/workflows/staging.yml"
        ]

        for path in excludedPaths {
            #expect(!FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path))
        }
    }

    @Test
    func ciIsReadOnlyAndRunsPublicChecks() throws {
        let ci = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let codeowners = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".github/CODEOWNERS"),
            encoding: .utf8
        )
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/antrum"),
            encoding: .utf8
        )

        for job in ["lint", "secret-scan", "dependency-review", "test"] {
            #expect(ci.contains("  \(job):"))
        }
        #expect(ci.contains("contents: read"))
        #expect(!ci.contains("contents: write"))
        #expect(!ci.contains("workflow_run"))
        #expect(codeowners.contains("@coreyone"))
        #expect(!codeowners.contains("@coreyoneal"))
        #expect(script.contains("public-check"))
    }

    @Test
    func publicDocsDoNotPromiseSignedBinariesOrPublishPersonalEmail() throws {
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let security = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SECURITY.md"),
            encoding: .utf8
        )
        let notices = try String(
            contentsOf: repositoryRoot.appendingPathComponent("THIRD_PARTY_AND_MODEL_NOTICES.md"),
            encoding: .utf8
        )

        #expect(readme.contains("No signed or notarized macOS binaries"))
        #expect(security.contains("private vulnerability reporting"))
        #expect(notices.contains("not distribute"))
        let privateEmail = "corey.oneal" + "@gmail.com"
        #expect(!readme.contains(privateEmail))
        #expect(!security.contains(privateEmail))
    }
}
