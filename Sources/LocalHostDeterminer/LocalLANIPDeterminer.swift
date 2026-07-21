import Foundation
import Darwin

public enum LocalLANIPDeterminer {
    /// IPv4 на en0 (Ethernet/Wi-Fi на mac mini), fallback на en1.
    /// nil если LAN-интерфейс без IPv4 — на CI это аномалия.
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
