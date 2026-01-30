import PackagePlugin

@main
struct DuplicateDetector: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceFiles = target.sourceModule?.sourceFiles else { return [] }
        let tool = try context.tool(named: "DuplicateDetectorTool")

        // collect swift source files
        let swiftFiles = sourceFiles.map(\.path).filter { $0.extension == "swift" }
        return createSingleCommand(for: swiftFiles, in: context.pluginWorkDirectory, with: tool.path).map { [$0] } ?? []
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension DuplicateDetector: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "DuplicateDetectorTool")

        let swiftFiles = target.inputFiles.map(\.path).filter { $0.extension == "swift" }
        return createSingleCommand(for: swiftFiles, in: context.pluginWorkDirectory, with: tool.path).map { [$0] } ?? []
    }
}

#endif

extension DuplicateDetector {
    func createSingleCommand(for swiftFiles: [Path], in outputDirectoryPath: Path, with toolPath: Path) -> Command? {
        guard !swiftFiles.isEmpty else { return nil }
        let stamp = outputDirectoryPath.appending("duplicate-detector.stamp")

        // pass all swift file paths followed by -o <stamp>
        var arguments: [String] = swiftFiles.map { "\($0)" }
        arguments.append("-o")
        arguments.append("\(stamp)")

        return .buildCommand(
            displayName: "Detect duplicate extension logic",
            executable: toolPath,
            arguments: arguments,
            inputFiles: swiftFiles,
            outputFiles: [stamp]
        )
    }
}
