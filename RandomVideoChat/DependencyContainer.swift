import Foundation
import SwiftUI

// MARK: - Dependency Container
/// 앱 전체의 의존성을 관리하는 중앙 컨테이너
/// 싱글톤 인스턴스들에 대한 통합 접근점을 제공
final class DependencyContainer {
    static let shared = DependencyContainer()

    // MARK: - Managers
    private(set) lazy var userManager: UserManager = .shared
    private(set) lazy var matchingManager: MatchingManager = .shared
    private(set) lazy var agoraManager: AgoraManager = .shared
    private(set) lazy var contentModerationManager: ContentModerationManager = .shared
    private(set) lazy var performanceMonitor: PerformanceMonitor = .shared
    private(set) lazy var imageCacheManager: ImageCacheManager = .shared

    // MARK: - Services
    private(set) lazy var tokenService: AgoraTokenService = .shared

    private init() {
        AppLogger.app.debug("DependencyContainer 초기화")
    }

    // MARK: - Configuration
    enum Environment {
        case development
        case production

        static var current: Environment {
            #if DEBUG
            return .development
            #else
            return .production
            #endif
        }
    }

    var environment: Environment {
        Environment.current
    }

    var isDevelopment: Bool {
        environment == .development
    }
}

// MARK: - SwiftUI Environment Key
private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue = DependencyContainer.shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - Convenience Extensions
extension View {
    /// 의존성 컨테이너에 쉽게 접근하기 위한 뷰 익스텐션
    func withDependencies() -> some View {
        self.environment(\.dependencies, DependencyContainer.shared)
    }
}
