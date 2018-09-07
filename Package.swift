// swift-tools-version:4.1

import PackageDescription

let package = Package(
    name: "AvitoUITestRunner",
    products: [
        .executable(name: "AvitoRunner", targets: ["AvitoRunner"]),
        .executable(name: "fake_fbxctest", targets: ["FakeFbxctest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.2.1"),
        .package(url: "https://github.com/beefon/Shout", .branch("master")),
        .package(url: "https://github.com/httpswift/swifter.git", .branch("stable")),
        .package(url: "https://github.com/weichsel/ZIPFoundation/", from: "0.9.6"),
    ],
    targets: [
        .target(name: "Ansi", dependencies: []),
        
        .target(
            name: "ArgumentsParser",
            dependencies: [
                "Extensions",
                "Logging",
                "Models",
                "RuntimeDump",
                "Utility"
            ]),
        
        .target(
            name: "AvitoRunner",
            dependencies: [
                "ArgumentsParser",
                "ChromeTracing",
                "Deployer",
                "DistRun",
                "DistWork",
                "JunitReporting",
                "LaunchdUtils",
                "ModelFactories",
                "Models",
                "ProcessController",
                "SSHDeployer",
                "ScheduleStrategy",
                "Scheduler"
            ]),
        .testTarget(
            name: "AvitoRunnerTests",
            dependencies: [
                "Extensions",
                "SimulatorPool"
            ]),
        
        .target(
            name: "ChromeTracing",
            dependencies: [
                "Models"
            ]),
        
        .target(
            name: "Deployer",
            dependencies: [
                "Extensions",
                "Logging",
                "Utility",
                "ZIPFoundation",
            ]),
        .testTarget(
            name: "DeployerTests",
            dependencies: [
                "Deployer"
            ]),
        
        .target(
            name: "DistRun",
            dependencies: [
                "Deployer",
                "Extensions",
                "HostDeterminer",
                "LaunchdUtils",
                "Logging",
                "Models",
                "RESTMethods",
                "RuntimeDump",
                "ScheduleStrategy",
                "SSHDeployer",
                "Swifter",
                "SynchronousWaiter",
                "Utility"
            ]),
        .testTarget(
            name: "DistRunTests",
            dependencies: [
                "Deployer",
                "DistRun",
                "ModelFactories"
            ]),
        
        .target(
            name: "DistWork",
            dependencies: [
                "Extensions",
                "Logging",
                "ModelFactories",
                "Models",
                "RESTMethods",
                "Scheduler",
                "SimulatorPool",
                "SynchronousWaiter",
                "Utility"
            ]),
        .testTarget(
            name: "DistWorkTests",
            dependencies: [
                "DistWork",
                "Models",
                "RESTMethods",
                "Swifter",
                "SynchronousWaiter"
            ]),
        
        .target(
            name: "Extensions",
            dependencies: []),
        .testTarget(
            name: "ExtensionsTests",
            dependencies: [
                "Extensions",
                "Utility"
            ]),
        
        .target(
            name: "FakeFbxctest",
            dependencies: [
                "Extensions",
                "Logging",
                "TestingFakeFbxctest"
            ]
        ),
        .target(
            name: "fbxctest",
            dependencies: [
                "Ansi",
                "JSONStream",
                "HostDeterminer",
                "Logging",
                "ProcessController",
                "Utility"
            ]),
        .target(
            name: "TestingFakeFbxctest",
            dependencies: [
                "Extensions",
                "fbxctest",
                "Logging"
            ]),
        
        .target(
            name: "FileCache",
            dependencies: [
                "Extensions",
                "Utility"
            ]),
        .testTarget(
            name: "FileCacheTests",
            dependencies: [
                "FileCache"
            ]),
        
        .target(
            name: "HostDeterminer",
            dependencies: [
                "Logging"
            ]),
        
        .target(
            name: "JSONStream",
            dependencies: []),
        .testTarget(
            name: "JSONStreamTests",
            dependencies: [
                "Utility",
                "JSONStream"
            ]),
        
        .target(
            name: "JunitReporting",
            dependencies: []),
        .testTarget(
            name: "JunitReportingTests",
            dependencies: [
                "Extensions",
                "JunitReporting"
            ]),
        
        .target(
            name: "LaunchdUtils",
            dependencies: []),
        .testTarget(
            name: "LaunchdUtilsTests",
            dependencies: [
                "LaunchdUtils"
            ]),
        
        .target(
            name: "ListeningSemaphore",
            dependencies: [
            ]),
        .testTarget(
            name: "ListeningSemaphoreTests",
            dependencies: [
                "ListeningSemaphore"
            ]),
        
        .target(
            name: "Logging",
            dependencies: [
                "Ansi"
            ]),
        
        .target(
            name: "ModelFactories",
            dependencies: [
                "Extensions",
                "FileCache",
                "Models",
                "ProcessController",
                "URLResource"
            ]),
        
        .target(
            name: "Models",
            dependencies: []),
        
        .target(
            name: "ProcessController",
            dependencies: [
                "Extensions",
                "Logging"
            ]),
        
        .target(
            name: "RESTMethods",
            dependencies: [
                "Models"
            ]),
        
        .target(
            name: "Runner",
            dependencies: [
                "fbxctest",
                "HostDeterminer",
                "Logging",
                "Models",
                "SimulatorPool"
            ]),
        .testTarget(
            name: "RunnerTests",
            dependencies: [
                "Extensions",
                "Models",
                "Runner",
                "ScheduleStrategy",
                "SimulatorPool",
                "TestingFakeFbxctest"
            ]
        ),
        
        .target(
            name: "RuntimeDump",
            dependencies: [
                "Models",
                "Runner"
            ]),
        
        .target(
            name: "Scheduler",
            dependencies: [
                "ListeningSemaphore",
                "Logging",
                "Models",
                "Runner",
                "RuntimeDump",
                "ScheduleStrategy",
                "SimulatorPool"
            ]),
        
        .target(
            name: "ScheduleStrategy",
            dependencies: [
                "Extensions",
                "Logging",
                "Models"
            ]),
        .testTarget(
            name: "ScheduleStrategyTests",
            dependencies: ["ScheduleStrategy"]),
        
        .target(
            name: "SimulatorPool",
            dependencies: [
                "Extensions",
                "fbxctest",
                "Logging",
                "Models",
                "ProcessController",
                "Utility"
            ]),
        .testTarget(
            name: "SimulatorPoolTests",
            dependencies: [
                "Models",
                "SimulatorPool",
                "SynchronousWaiter"
            ]),
        
        .target(
            name: "SSHDeployer",
            dependencies: [
                "Ansi",
                "Extensions",
                "Logging",
                "Utility",
                "Deployer",
                "Shout"
            ]),
        .testTarget(
            name: "SSHDeployerTests",
            dependencies: [
                "SSHDeployer"
            ]),
        
        .target(
            name: "SynchronousWaiter",
            dependencies: []),
        .testTarget(
            name: "SynchronousWaiterTests",
            dependencies: ["SynchronousWaiter"]),
        
        .target(
            name: "URLResource",
            dependencies: [
                "FileCache",
                "Logging",
                "Utility"
            ]),
        .testTarget(
            name: "URLResourceTests",
            dependencies: [
                "FileCache",
                "Swifter",
                "URLResource",
                "Utility"
            ])
    ]
)