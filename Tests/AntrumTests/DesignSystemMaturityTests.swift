import Foundation
import Testing

@Suite("Design system maturity")
struct DesignSystemMaturityTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test
    func designSourceOfTruthNamesCurrentVisualDirection() throws {
        let design = try String(
            contentsOf: repositoryRoot.appendingPathComponent("DESIGN.md"),
            encoding: .utf8
        )

        #expect(design.contains("dark graphite"))
        #expect(design.contains("Liquid Glass"))
        #expect(design.contains("native macOS controls"))
        #expect(design.contains("Do not return to the older warm paper pixel system"))
    }

    @Test
    func machineReadableTokensDeclareFoundations() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("design/tokens.json"))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["name"] as? String == "Antrum Dark Graphite Liquid Glass")
        #expect(object["version"] as? String == "alpha")

        let color = try #require(object["color"] as? [String: Any])
        let typography = try #require(object["typography"] as? [String: Any])
        let component = try #require(object["component"] as? [String: Any])

        #expect(color["waveform"] as? [String] != nil)
        #expect(typography["family"] as? String == "SF Mono, Menlo, Monaco, monospace")
        #expect(component["minimumTarget"] as? Int == 44)
    }

    @Test
    func designOperationalDocsCoverAdoptionAndGovernance() throws {
        let requiredPaths = [
            "docs/design/COMPONENTS.md",
            "docs/design/WORKFLOWS.md",
            "docs/design/ACCESSIBILITY.md",
            "docs/design/CUSTOMIZATION.md",
            "docs/design/VISUAL_QA.md",
            "docs/design/PR_CHECKLIST.md",
            "docs/adr/0006-visual-system-direction.md"
        ]

        for path in requiredPaths {
            let text = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test
    func visualQADocKeepsScreenshotsOutOfTheRepositoryByDefault() throws {
        let makefile = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let visualQA = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/design/VISUAL_QA.md"),
            encoding: .utf8
        )

        #expect(makefile.contains("run:"))
        #expect(visualQA.contains("Keep captures local"))
        #expect(!makefile.contains("visual-smoke"))
    }
}
