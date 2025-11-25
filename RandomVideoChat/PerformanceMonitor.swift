import Foundation
import os.log
import Network

#if canImport(FirebasePerformance)
import FirebasePerformance
#endif

class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    private let logger = Logger(subsystem: "com.5sec.app", category: "Performance")

    // 네트워크 모니터링
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "com.5sec.networkMonitor")

    // 현재 네트워크 상태
    @Published private(set) var currentNetworkQuality: NetworkQuality = .unknown
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionType: ConnectionType = .unknown

    private init() {
        startNetworkMonitoring()
    }

    deinit {
        stopNetworkMonitoring()
    }

    // MARK: - Network Monitoring
    func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()

        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path)
            }
        }

        networkMonitor?.start(queue: networkQueue)
        print("📶 네트워크 모니터링 시작")
    }

    func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
        print("📶 네트워크 모니터링 중지")
    }

    private func updateNetworkStatus(_ path: NWPath) {
        // 연결 상태
        let wasConnected = isConnected
        isConnected = path.status == .satisfied

        // 연결 타입 확인
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }

        // 네트워크 품질 평가
        let previousQuality = currentNetworkQuality
        currentNetworkQuality = evaluateNetworkQuality(path)

        // 상태 변화 로깅
        if wasConnected != isConnected || previousQuality != currentNetworkQuality {
            print("📶 네트워크 상태 변경:")
            print("   - 연결: \(isConnected ? "✅" : "❌")")
            print("   - 타입: \(connectionType.description)")
            print("   - 품질: \(currentNetworkQuality.description)")

            // 품질 변화 알림
            NotificationCenter.default.post(
                name: .networkQualityChanged,
                object: nil,
                userInfo: ["quality": currentNetworkQuality]
            )
        }
    }

    private func evaluateNetworkQuality(_ path: NWPath) -> NetworkQuality {
        guard path.status == .satisfied else {
            return .unknown
        }

        // 제약 조건 확인
        if path.isConstrained {
            // 저데이터 모드 또는 제한된 연결
            return .poor
        }

        if path.isExpensive {
            // 셀룰러 또는 비용이 드는 연결
            if path.usesInterfaceType(.cellular) {
                // 셀룰러는 기본적으로 good으로 평가
                return .good
            }
            return .good
        }

        // WiFi 연결
        if path.usesInterfaceType(.wifi) {
            return .excellent
        }

        // 유선 연결
        if path.usesInterfaceType(.wiredEthernet) {
            return .excellent
        }

        return .good
    }

    // MARK: - Public API
    func getNetworkQuality() -> NetworkQuality {
        return currentNetworkQuality
    }

    func isNetworkAvailable() -> Bool {
        return isConnected
    }

    // MARK: - Query Performance Measurement
    static func measureQuery<T>(_ name: String, block: () async throws -> T) async rethrows -> T {
        #if canImport(FirebasePerformance)
        let trace = Performance.startTrace(name: name)
        #endif

        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

            #if canImport(FirebasePerformance)
            trace?.setValue(Int64(timeElapsed * 1000), forMetric: "duration_ms")
            trace?.stop()
            #endif

            #if DEBUG
            print("📊 Query '\(name)' took: \(String(format: "%.2f", timeElapsed * 1000))ms")
            #endif
        }

        return try await block()
    }

    // MARK: - Memory Usage Monitoring
    func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024 / 1024 // MB
        } else {
            return 0
        }
    }

    // MARK: - Performance Metrics Collection
    struct Metrics {
        var averageMatchingTime: Double = 0
        var videoCallDropRate: Double = 0
        var memoryUsage: Double = 0
        var firebaseQueryTime: Double = 0
        var matchingSuccessRate: Double = 0
    }

    private var metrics = Metrics()

    func updateMatchingTime(_ time: Double) {
        metrics.averageMatchingTime = (metrics.averageMatchingTime + time) / 2
    }

    func updateVideoDropRate(_ rate: Double) {
        metrics.videoCallDropRate = rate
    }

    func updateMatchingSuccessRate(_ rate: Double) {
        metrics.matchingSuccessRate = rate
    }

    func logCurrentMetrics() {
        metrics.memoryUsage = getCurrentMemoryUsage()

        logger.info("""
        📊 Performance Metrics:
        - Network: \(self.currentNetworkQuality.description)
        - Avg Matching Time: \(String(format: "%.2f", self.metrics.averageMatchingTime))s
        - Video Drop Rate: \(String(format: "%.1f", self.metrics.videoCallDropRate))%
        - Memory Usage: \(String(format: "%.1f", self.metrics.memoryUsage))MB
        - Matching Success: \(String(format: "%.1f", self.metrics.matchingSuccessRate))%
        """)

        #if DEBUG
        print("""
        📊 Performance Metrics:
        - Network: \(currentNetworkQuality.description)
        - Avg Matching Time: \(String(format: "%.2f", metrics.averageMatchingTime))s
        - Video Drop Rate: \(String(format: "%.1f", metrics.videoCallDropRate))%
        - Memory Usage: \(String(format: "%.1f", metrics.memoryUsage))MB
        - Matching Success: \(String(format: "%.1f", metrics.matchingSuccessRate))%
        """)
        #endif
    }

    // MARK: - Automatic Performance Monitoring
    private var monitoringTimer: Timer?

    func startPerformanceMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.logCurrentMetrics()
        }
    }

    func stopPerformanceMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
}

// MARK: - Network Quality Enum
enum NetworkQuality {
    case excellent
    case good
    case poor
    case unknown

    var description: String {
        switch self {
        case .excellent: return "최고"
        case .good: return "양호"
        case .poor: return "나쁨"
        case .unknown: return "알 수 없음"
        }
    }

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "yellow"
        case .poor: return "red"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Connection Type Enum
enum ConnectionType {
    case wifi
    case cellular
    case ethernet
    case unknown

    var description: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "셀룰러"
        case .ethernet: return "유선"
        case .unknown: return "알 수 없음"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let networkQualityChanged = Notification.Name("networkQualityChanged")
}
