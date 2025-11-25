import Foundation
import FirebaseFunctions
import FirebaseDatabase

/// Agora 토큰 관리 서비스
/// Firebase Cloud Functions를 통해 안전하게 토큰을 생성하고 갱신합니다.
class AgoraTokenService {
    static let shared = AgoraTokenService()

    private lazy var functions = Functions.functions()

    // 토큰 캐싱
    private var cachedToken: String?
    private var cachedChannelName: String?
    private var tokenExpireTime: Date?

    // 토큰 갱신 타이머
    private var refreshTimer: Timer?

    // 토큰 만료 전 갱신 여유 시간 (5분)
    private let refreshBuffer: TimeInterval = 300

    private init() {}

    // MARK: - Public Methods

    /// 새 토큰 생성 요청
    func generateToken(
        channelName: String,
        uid: UInt = 0,
        completion: @escaping (Result<TokenResponse, TokenError>) -> Void
    ) {
        AppLogger.token.info("토큰 생성 요청 - 채널: \(channelName)")

        // 캐시된 토큰이 유효하면 재사용
        if let cached = cachedToken,
           cachedChannelName == channelName,
           let expireTime = tokenExpireTime,
           expireTime.timeIntervalSinceNow > refreshBuffer {
            AppLogger.token.debug("캐시된 토큰 사용")
            completion(.success(TokenResponse(token: cached, expireTimestamp: Int(expireTime.timeIntervalSince1970))))
            return
        }

        let data: [String: Any] = [
            "channelName": channelName,
            "uid": uid,
            "role": "publisher",
            "expireTime": 3600
        ]

        functions.httpsCallable("generateAgoraToken").call(data) { [weak self] result, error in
            if let error = error as NSError? {
                AppLogger.token.error("토큰 생성 실패", error: error)

                let tokenError: TokenError
                switch error.domain {
                case FunctionsErrorDomain:
                    let code = FunctionsErrorCode(rawValue: error.code)
                    switch code {
                    case .unauthenticated:
                        tokenError = .unauthenticated
                    case .invalidArgument:
                        tokenError = .invalidArgument(error.localizedDescription)
                    default:
                        tokenError = .serverError(error.localizedDescription)
                    }
                default:
                    tokenError = .networkError(error.localizedDescription)
                }

                completion(.failure(tokenError))
                return
            }

            guard let data = result?.data as? [String: Any],
                  let token = data["token"] as? String,
                  let expireTimestamp = data["expireTimestamp"] as? Int else {
                AppLogger.token.error("토큰 응답 파싱 실패")
                completion(.failure(.parseError))
                return
            }

            AppLogger.token.notice("토큰 생성 성공")

            // 캐싱
            self?.cachedToken = token
            self?.cachedChannelName = channelName
            self?.tokenExpireTime = Date(timeIntervalSince1970: TimeInterval(expireTimestamp))

            // 자동 갱신 타이머 설정
            self?.scheduleTokenRefresh(channelName: channelName, uid: uid)

            completion(.success(TokenResponse(token: token, expireTimestamp: expireTimestamp)))
        }
    }

    /// 토큰 갱신 요청
    func refreshToken(
        channelName: String,
        uid: UInt = 0,
        completion: @escaping (Result<TokenResponse, TokenError>) -> Void
    ) {
        AppLogger.token.info("토큰 갱신 요청 - 채널: \(channelName)")

        let data: [String: Any] = [
            "channelName": channelName,
            "uid": uid
        ]

        functions.httpsCallable("refreshAgoraToken").call(data) { [weak self] result, error in
            if let error = error {
                AppLogger.token.error("토큰 갱신 실패", error: error)
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let data = result?.data as? [String: Any],
                  let token = data["token"] as? String,
                  let expireTimestamp = data["expireTimestamp"] as? Int else {
                completion(.failure(.parseError))
                return
            }

            AppLogger.token.notice("토큰 갱신 성공")

            // 캐시 업데이트
            self?.cachedToken = token
            self?.tokenExpireTime = Date(timeIntervalSince1970: TimeInterval(expireTimestamp))

            completion(.success(TokenResponse(token: token, expireTimestamp: expireTimestamp)))
        }
    }

    /// 매칭 데이터에서 토큰 가져오기
    func getTokenFromMatch(matchId: String, completion: @escaping (String?) -> Void) {
        let ref = Database.database().reference().child("matches").child(matchId)

        ref.observeSingleEvent(of: .value) { snapshot in
            guard let data = snapshot.value as? [String: Any],
                  let token = data["agoraToken"] as? String else {
                AppLogger.token.warning("매칭 데이터에 토큰 없음 - 새로 생성 필요")
                completion(nil)
                return
            }

            AppLogger.token.debug("매칭 데이터에서 토큰 획득")
            completion(token)
        }
    }

    /// 토큰 캐시 초기화
    func clearCache() {
        cachedToken = nil
        cachedChannelName = nil
        tokenExpireTime = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        AppLogger.token.debug("토큰 캐시 초기화")
    }

    // MARK: - Private Methods

    private func scheduleTokenRefresh(channelName: String, uid: UInt) {
        refreshTimer?.invalidate()

        guard let expireTime = tokenExpireTime else { return }

        // 만료 5분 전에 갱신
        let refreshTime = expireTime.addingTimeInterval(-refreshBuffer)
        let delay = refreshTime.timeIntervalSinceNow

        guard delay > 0 else {
            refreshToken(channelName: channelName, uid: uid) { _ in }
            return
        }

        AppLogger.token.debug("토큰 갱신 예약 - \(Int(delay))초 후")

        refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refreshToken(channelName: channelName, uid: uid) { result in
                switch result {
                case .success(let response):
                    NotificationCenter.default.post(
                        name: .agoraTokenRefreshed,
                        object: nil,
                        userInfo: ["token": response.token]
                    )
                case .failure(let error):
                    AppLogger.token.error("자동 토큰 갱신 실패: \(error.localizedDescription)")
                    NotificationCenter.default.post(
                        name: .agoraTokenRefreshFailed,
                        object: nil
                    )
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct TokenResponse {
    let token: String
    let expireTimestamp: Int

    var expireDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expireTimestamp))
    }
}

enum TokenError: Error, LocalizedError {
    case unauthenticated
    case invalidArgument(String)
    case serverError(String)
    case networkError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "인증이 필요합니다. 다시 로그인해주세요."
        case .invalidArgument(let message):
            return "잘못된 요청: \(message)"
        case .serverError(let message):
            return "서버 오류: \(message)"
        case .networkError(let message):
            return "네트워크 오류: \(message)"
        case .parseError:
            return "응답을 처리할 수 없습니다."
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let agoraTokenRefreshed = Notification.Name("agoraTokenRefreshed")
    static let agoraTokenRefreshFailed = Notification.Name("agoraTokenRefreshFailed")
}
