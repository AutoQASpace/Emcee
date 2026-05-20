import Foundation
import Darwin

public enum LocalLANIPDeterminer {
    /// Returns IPv4 address of en0 (typically Ethernet/Wi-Fi on Mac mini workers);
    /// falls back to en1 if en0 has no IPv4. Returns nil if no LAN interface has IPv4 —
    /// on CI this is an anomaly, callers should fall back to LocalHostDeterminer.currentHostAddress.
    public static func ipv4OnLAN() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var en0: String?
        var en1: String?

        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            defer { cur = p.pointee.ifa_next }
            let entry = p.pointee
            guard entry.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let name = String(cString: entry.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                entry.ifa_addr,
                socklen_t(entry.ifa_addr.pointee.sa_len),
                &hostBuf,
                socklen_t(hostBuf.count),
                nil, 0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ip = String(cString: hostBuf)
            if name == "en0" { en0 = ip } else { en1 = ip }
        }

        return en0 ?? en1
    }
}
