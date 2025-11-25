import Foundation

// MARK: - App Error
/// 앱 전체에서 사용하는 통합 에러 타입
enum AppError: Error, LocalizedError {

    // MARK: - Authentication Errors
    case authenticationFailed(underlying: Error?)
    case userNotFound
    case sessionExpired

    // MARK: - Network Errors
    case networkUnavailable
    case serverError(statusCode: Int)
    case timeout
    case invalidResponse

    // MARK: - Matching Errors
    case matchingFailed(reason: String)
    case noUsersAvailable
    case matchingTimeout
    case alreadyMatching

    // MARK: - Video Call Errors
    case videoCallFailed(reason: String)
    case channelJoinFailed
    case tokenExpired
    case connectionLost

    // MARK: - Firebase Errors
    case firebaseError(underlying: Error)
    case databaseReadFailed
    case databaseWriteFailed

    // MARK: - User Errors
    case userBlocked
    case insufficientHearts
    case invalidUserData

    // MARK: - General Errors
    case unknown(underlying: Error?)
    case cancelled

    // MARK: - LocalizedError
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let error):
            return "인증 실패: \(error?.localizedDescription ?? "알 수 없는 오류")"
        case .userNotFound:
            return "사용자를 찾을 수 없습니다"
        case .sessionExpired:
            return "세션이 만료되었습니다"

        case .networkUnavailable:
            return "네트워크에 연결할 수 없습니다"
        case .serverError(let code):
            return "서버 오류 (코드: \(code))"
        case .timeout:
            return "요청 시간이 초과되었습니다"
        case .invalidResponse:
            return "잘못된 서버 응답"

        case .matchingFailed(let reason):
            return "매칭 실패: \(reason)"
        case .noUsersAvailable:
            return "현재 대기 중인 사용자가 없습니다"
        case .matchingTimeout:
            return "매칭 시간이 초과되었습니다"
        case .alreadyMatching:
            return "이미 매칭 중입니다"

        case .videoCallFailed(let reason):
            return "영상 통화 실패: \(reason)"
        case .channelJoinFailed:
            return "채널 참가 실패"
        case .tokenExpired:
            return "토큰이 만료되었습니다"
        case .connectionLost:
            return "연결이 끊어졌습니다"

        case .firebaseError(let error):
            return "Firebase 오류: \(error.localizedDescription)"
        case .databaseReadFailed:
            return "데이터 읽기 실패"
        case .databaseWriteFailed:
            return "데이터 쓰기 실패"

        case .userBlocked:
            return "차단된 사용자입니다"
        case .insufficientHearts:
            return "하트가 부족합니다"
        case .invalidUserData:
            return "잘못된 사용자 데이터"

        case .unknown(let error):
            return "알 수 없는 오류: \(error?.localizedDescription ?? "")"
        case .cancelled:
            return "작업이 취소되었습니다"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "네트워크 연결을 확인하고 다시 시도해주세요"
        case .sessionExpired:
            return "앱을 다시 시작해주세요"
        case .matchingTimeout, .noUsersAvailable:
            return "잠시 후 다시 시도해주세요"
        case .tokenExpired:
            return "앱을 다시 시작하거나 다시 시도해주세요"
        case .insufficientHearts:
            return "하트를 충전해주세요"
        default:
            return nil
        }
    }
}

// MARK: - Error Conversion Extensions
extension Error {
    /// 일반 Error를 AppError로 변환
    var asAppError: AppError {
        if let appError = self as? AppError {
            return appError
        }
        return .unknown(underlying: self)
    }
}

// MARK: - Result Extension
extension Result where Failure == AppError {
    /// 성공 또는 에러 로깅
    func logResult(category: AppLogger.Category = .app) {
        switch self {
        case .success:
            break
        case .failure(let error):
            switch category {
            case .auth:
                AppLogger.auth.error(error.localizedDescription)
            case .matching:
                AppLogger.matching.error(error.localizedDescription)
            case .agora:
                AppLogger.agora.error(error.localizedDescription)
            case .firebase:
                AppLogger.firebase.error(error.localizedDescription)
            case .user:
                AppLogger.user.error(error.localizedDescription)
            case .network:
                AppLogger.network.error(error.localizedDescription)
            default:
                AppLogger.app.error(error.localizedDescription)
            }
        }
    }
}
