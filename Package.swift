// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CodexTaskMonitor", platforms: [.macOS(.v13)], products: [
    .executable(name: "CodexTaskMonitor", targets: ["CodexTaskMonitor"])
], targets: [
    .systemLibrary(name: "CSQLite"),
    .target(name: "MonitorCore", dependencies: ["CSQLite"]),
    .executableTarget(name: "CodexTaskMonitor", dependencies: ["MonitorCore"]),
    .executableTarget(name: "MonitorCoreChecks", dependencies: ["MonitorCore", "CSQLite"], path: "Tests/MonitorCoreTests")
])
