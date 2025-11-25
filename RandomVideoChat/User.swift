import Foundation
import FirebaseFirestore

// MARK: - Gender
/// 사용자 성별을 나타내는 열거형
/// - 매칭 필터링에 사용
/// - Codable 지원으로 Firestore 저장 가능
enum Gender: String, CaseIterable, Codable {
    case male = "male"
    case female = "female"
    
    var icon: String {
        switch self {
        case .male:
            return "person.fill"
        case .female:
            return "person.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .male:
            return "남"
        case .female:
            return "여"
        }
    }
}

// MARK: - User Model
/// 사용자 정보를 담는 데이터 모델
/// - Firestore users 컬렉션에 저장
/// - 하트 개수, 차단 목록, 성별 정보 포함
struct User: Codable {
    let uid: String
    let email: String?
    let displayName: String?
    var heartCount: Int
    let createdAt: Date
    var blockedUsers: [String]
    var gender: Gender?
    var preferredGender: Gender?
    
    init(uid: String, email: String? = nil, displayName: String? = nil) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.heartCount = 3  // 초기 하트 3개
        self.createdAt = Date()
        self.blockedUsers = []
        self.gender = nil
        self.preferredGender = nil
    }
    
    // Firestore 데이터로 변환
    var dictionary: [String: Any] {
        return [
            "uid": uid,
            "email": email ?? "",
            "displayName": displayName ?? "",
            "heartCount": heartCount,
            "createdAt": Timestamp(date: createdAt),
            "blockedUsers": blockedUsers,
            "gender": gender?.rawValue ?? "",
            "preferredGender": preferredGender?.rawValue ?? ""
        ]
    }
}
