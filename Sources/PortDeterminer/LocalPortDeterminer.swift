import Darwin
import Foundation
import EmceeLogging
import SocketModels

public final class LocalPortDeterminer {
    private let logger: ContextualLogger
    private let portRange: ClosedRange<SocketModels.Port>
    
    public init(
        logger: ContextualLogger,
        portRange: ClosedRange<SocketModels.Port>
    ) {
        self.logger = logger
        self.portRange = portRange
    }
    
    public enum LocalPortDeterminerError: Error, CustomStringConvertible {
        case noAvailablePorts(portRange: ClosedRange<SocketModels.Port>)
        
        public var description: String {
            switch self {
            case .noAvailablePorts(let portRange):
                return "No free TCP ports found in range \(portRange)"
            }
        }
    }
    
    public func availableLocalPort() throws -> SocketModels.Port {
        for port in portRange {
            logger.debug("Checking availability of local port \(port)")
            if isPortAvailable(port: UInt16(port.value)) {
                logger.debug("Port \(port) appears to be available")
                return port
            }
        }
        throw LocalPortDeterminerError.noAvailablePorts(portRange: portRange)
    }
    
    private func isPortAvailable(port: in_port_t) -> Bool {
        // Порт считаем занятым, если на него удаётся установить TCP-соединение
        // (значит на нём кто-то слушает).
        //
        // Нельзя определять занятость через listen-сокет `Socket.tcpSocketForListen`:
        // он ставит SO_REUSEADDR и успешно биндится ПОВЕРХ уже слушающего процесса,
        // ложно сообщая «порт свободен». Из-за этого новый queue server садился на
        // порт уже работающего queue другой версии — запросы /queueVersion отвечал
        // старый процесс, новый оставался необнаружимым (таймаут «Wait for remote
        // queue to start»).
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFileDescriptor >= 0 else { return false }
        defer { close(socketFileDescriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // connect успешен (0) → есть слушатель → порт занят → недоступен.
        return connectResult != 0
    }
}
