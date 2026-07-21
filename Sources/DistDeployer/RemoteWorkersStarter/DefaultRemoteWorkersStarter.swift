import Deployer
import FileSystem
import Foundation
import EmceeLogging
import PathLib
import QueueModels
import SocketModels
import Tmp
import UniqueIdentifierGenerator
import Zip

public final class DefaultRemoteWorkersStarter: RemoteWorkerStarter {
    private let auxiliaryBinaries: [String]?
    private let auxiliaryBinariesPath: String?
    private let deploymentDestination: DeploymentDestination
    private let emceeVersion: Version
    private let fileSystem: FileSystem
    private let logger: ContextualLogger
    private let tempFolder: TemporaryFolder
    private let uniqueIdentifierGenerator: UniqueIdentifierGenerator
    private let zipCompressor: ZipCompressor

    public init(
        auxiliaryBinaries: [String]? = nil,
        auxiliaryBinariesPath: String? = nil,
        deploymentDestination: DeploymentDestination,
        emceeVersion: Version,
        fileSystem: FileSystem,
        logger: ContextualLogger,
        tempFolder: TemporaryFolder,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator,
        zipCompressor: ZipCompressor
    ) {
        self.auxiliaryBinaries = auxiliaryBinaries
        self.auxiliaryBinariesPath = auxiliaryBinariesPath
        self.deploymentDestination = deploymentDestination
        self.emceeVersion = emceeVersion
        self.fileSystem = fileSystem
        self.logger = logger
        self.tempFolder = tempFolder
        self.uniqueIdentifierGenerator = uniqueIdentifierGenerator
        self.zipCompressor = zipCompressor
    }
    
    public func deployAndStartWorker(
        queueAddress: SocketAddress
    ) throws {
        let deployablesGenerator = DeployablesGenerator(
            emceeVersion: emceeVersion,
            remoteEmceeBinaryName: "EmceeWorker"
        )
        let deployableItems = try deployablesGenerator.deployables()
        let emceeBinaryDeployableItem = try deployablesGenerator.runnerTool()
        
        let launchdPlist = RemoteWorkerLaunchdPlist(
            deploymentDestination: deploymentDestination,
            emceeVersion: emceeVersion,
            executableDeployableItem: emceeBinaryDeployableItem,
            queueAddress: queueAddress
        )
        let launchdPlistTargetPath = "launchd_\(deploymentDestination.workerId.value).plist"
        
        let filePath = try tempFolder.createFile(
            filename: launchdPlistTargetPath,
            contents: try launchdPlist.plistData()
        )
        
        logger.debug("Deploying to \(deploymentDestination)")

        var auxiliaryDeployableItems: [DeployableItem] = []
        if let binariesPath = auxiliaryBinariesPath, let binaries = auxiliaryBinaries {
            for binaryName in binaries {
                let sourcePath = AbsolutePath(binariesPath).appending(binaryName)
                let auxiliaryItem = DeployableItem(
                    name: "auxiliary_\(binaryName)",
                    files: [
                        DeployableFile(
                            source: sourcePath,
                            destination: RelativePath("auxiliary/\(binaryName)")
                        )
                    ]
                )
                auxiliaryDeployableItems.append(auxiliaryItem)
            }
        }

        let launchdDeployableItem = DeployableItem(
            name: "launchd_plist",
            files: [
                DeployableFile(
                    source: filePath,
                    destination: RelativePath(launchdPlistTargetPath)
                )
            ]
        )
        let launchctlDeployableCommands = LaunchctlDeployableCommands(
            launchdPlistDeployableItem: launchdDeployableItem,
            plistFilename: launchdPlistTargetPath
        )
        
        let deployer = DistDeployer(
            deploymentId: emceeVersion.value,
            deploymentDestination: deploymentDestination,
            deployableItems: deployableItems + auxiliaryDeployableItems + [launchdDeployableItem],
            deployableCommands: [
                launchctlDeployableCommands.forceUnloadFromBackgroundCommand(),
                [
                    "sleep", "2"        // launchctl is async, so we have to wait :(
                ],
                launchctlDeployableCommands.forceLoadInBackgroundCommand()
            ],
            fileSystem: fileSystem,
            logger: logger,
            tempFolder: tempFolder,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator,
            zipCompressor: zipCompressor
        )
        
        try deployer.deploy()
    }
}
