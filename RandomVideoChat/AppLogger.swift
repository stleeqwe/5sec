import Foundation
import os.log

// MARK: - App Logger
/// 중앙화된 로깅 시스템
/// os.log 기반으로 구현하여 성능 최적화 및 시스템 통합 로깅 지원
struct AppLogger {

    // MARK: - Log Categories
    enum Category: String {
        case app = "App"
        case auth = "Auth"
        case matching = "Matching"
        case agora = "Agora"
        case firebase = "Firebase"
        case camera = "Camera"
        case user = "User"
        case performance = "Performance"
        case ui = "UI"
        case network = "Network"
        case token = "Token"
        case moderation = "Moderation"

        var logger: Logger {
            Logger(subsystem: AppLogger.subsystem, category: rawValue)
        }
    }

    // MARK: - Properties
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.5sec.app"

    // MARK: - Category Loggers
    static let app = CategoryLogger(category: .app)
    static let auth = CategoryLogger(category: .auth)
    static let matching = CategoryLogger(category: .matching)
    static let agora = CategoryLogger(category: .agora)
    static let firebase = CategoryLogger(category: .firebase)
    static let camera = CategoryLogger(category: .camera)
    static let user = CategoryLogger(category: .user)
    static let performance = CategoryLogger(category: .performance)
    static let ui = CategoryLogger(category: .ui)
    static let network = CategoryLogger(category: .network)
    static let token = CategoryLogger(category: .token)
    static let moderation = CategoryLogger(category: .moderation)
}

// MARK: - Category Logger
/// 카테고리별 로깅을 처리하는 구조체
struct CategoryLogger {
    private let logger: Logger
    private let category: AppLogger.Category

    init(category: AppLogger.Category) {
        self.category = category
        self.logger = category.logger
    }

    // MARK: - Debug Level
    /// 개발 중 디버깅 목적의 상세 정보
    /// Release 빌드에서는 출력되지 않음
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        logger.debug("[\(fileName):\(line)] \(message)")
        #endif
    }

    // MARK: - Info Level
    /// 일반적인 실행 흐름 정보
    func info(_ message: String) {
        logger.info("\(message)")
    }

    // MARK: - Notice Level
    /// 중요한 이벤트 (성공, 완료 등)
    func notice(_ message: String) {
        logger.notice("✅ \(message)")
    }

    // MARK: - Warning Level
    /// 잠재적 문제 또는 비정상적인 상황
    func warning(_ message: String) {
        logger.warning("⚠️ \(message)")
    }

    // MARK: - Error Level
    /// 오류 발생 (복구 가능)
    func error(_ message: String, error: Error? = nil) {
        if let error = error {
            logger.error("❌ \(message): \(error.localizedDescription)")
        } else {
            logger.error("❌ \(message)")
        }
    }

    // MARK: - Fault Level
    /// 심각한 오류 (시스템 수준 문제)
    func fault(_ message: String) {
        logger.fault("🚨 \(message)")
    }

    // MARK: - Convenience Methods

    /// 함수 진입 로깅
    func enter(function: String = #function) {
        #if DEBUG
        logger.debug("➡️ Entering \(function)")
        #endif
    }

    /// 함수 종료 로깅
    func exit(function: String = #function) {
        #if DEBUG
        logger.debug("⬅️ Exiting \(function)")
        #endif
    }

    /// 성능 측정 시작
    func measureStart(_ operation: String) -> CFAbsoluteTime {
        let startTime = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        logger.debug("⏱ Starting: \(operation)")
        #endif
        return startTime
    }

    /// 성능 측정 종료 및 결과 로깅
    func measureEnd(_ operation: String, startTime: CFAbsoluteTime) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        #if DEBUG
        logger.debug("⏱ Completed: \(operation) in \(String(format: "%.2f", elapsed))ms")
        #endif
    }
}

// MARK: - Log Level Enum
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4
    case fault = 5

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .notice: return "✅"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .fault: return "🚨"
        }
    }
}

// MARK: - Signpost Support for Performance
extension CategoryLogger {
    /// 성능 추적을 위한 시그니처 포스트 시작
    func signpostBegin(_ name: StaticString, id: OSSignpostID = .exclusive) {
        #if DEBUG
        os_signpost(.begin, log: OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.5sec.app", category: "Performance"), name: name, signpostID: id)
        #endif
    }

    /// 성능 추적을 위한 시그니처 포스트 종료
    func signpostEnd(_ name: StaticString, id: OSSignpostID = .exclusive) {
        #if DEBUG
        os_signpost(.end, log: OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.5sec.app", category: "Performance"), name: name, signpostID: id)
        #endif
    }
}

// MARK: - Global Convenience Functions
/// 전역에서 빠르게 사용할 수 있는 로깅 함수들

#if DEBUG
/// Debug 레벨 로그 (DEBUG 빌드 전용)
func logDebug(_ message: String, category: AppLogger.Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
    let fileName = (file as NSString).lastPathComponent
    category.logger.debug("[\(fileName):\(line)] \(message)")
}
#endif

/// Info 레벨 로그
func logInfo(_ message: String, category: AppLogger.Category = .app) {
    category.logger.info("\(message)")
}

/// Warning 레벨 로그
func logWarning(_ message: String, category: AppLogger.Category = .app) {
    category.logger.warning("⚠️ \(message)")
}

/// Error 레벨 로그
func logError(_ message: String, category: AppLogger.Category = .app, error: Error? = nil) {
    if let error = error {
        category.logger.error("❌ \(message): \(error.localizedDescription)")
    } else {
        category.logger.error("❌ \(message)")
    }
}
