import Deployer
import DistDeployer
import EmceeLogging
import FileSystem
import Foundation
import QueueModels
import SocketModels
import SSHDeployer
import Tmp
import UniqueIdentifierGenerator
import Zip

public final class DefaultRemoteWorkerStarterProvider: RemoteWorkerStarterProvider {
    private let emceeVersion: Version
    private let fileSystem: FileSystem
    private let logger: ContextualLogger
    private let sshClientProvider: SSHClientProvider
    private let tempFolder: TemporaryFolder
    private let uniqueIdentifierGenerator: UniqueIdentifierGenerator
    private let workerDeploymentDestinations: [DeploymentDestination]
    private let zipCompressor: ZipCompressor
    private let auxiliaryBinariesPath: String?
    private let auxiliaryBinaries: [String]?

    public init(
        emceeVersion: Version,
        fileSystem: FileSystem,
        logger: ContextualLogger,
        sshClientProvider: SSHClientProvider,
        tempFolder: TemporaryFolder,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator,
        workerDeploymentDestinations: [DeploymentDestination],
        zipCompressor: ZipCompressor,
        auxiliaryBinariesPath: String? = nil,
        auxiliaryBinaries: [String]? = nil
    ) {
        self.emceeVersion = emceeVersion
        self.fileSystem = fileSystem
        self.logger = logger
        self.sshClientProvider = sshClientProvider
        self.tempFolder = tempFolder
        self.uniqueIdentifierGenerator = uniqueIdentifierGenerator
        self.workerDeploymentDestinations = workerDeploymentDestinations
        self.zipCompressor = zipCompressor
        self.auxiliaryBinariesPath = auxiliaryBinariesPath
        self.auxiliaryBinaries = auxiliaryBinaries
    }
    
    public enum DefaultRemoteWorkerStarterProviderError: Error, CustomStringConvertible {
        case noDeploymentDestinationForWorkerId(WorkerId)
        
        public var description: String {
            switch self {
            case .noDeploymentDestinationForWorkerId(let workerId):
                return "No known deployment destination is available for \(workerId)"
            }
        }
    }
    
    public func remoteWorkerStarter(
        workerId: WorkerId
    ) throws -> RemoteWorkerStarter {
        guard let deploymentDestination = workerDeploymentDestinations.first(where: { $0.workerId == workerId }) else {
            throw DefaultRemoteWorkerStarterProviderError.noDeploymentDestinationForWorkerId(workerId)
        }
        
        return DefaultRemoteWorkersStarter(
            auxiliaryBinaries: auxiliaryBinaries,
            auxiliaryBinariesPath: auxiliaryBinariesPath,
            sshClientProvider: sshClientProvider,
            deploymentDestination: deploymentDestination,
            emceeVersion: emceeVersion,
            fileSystem: fileSystem,
            logger: logger,
            tempFolder: tempFolder,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator,
            zipCompressor: zipCompressor
        )
    }
}
