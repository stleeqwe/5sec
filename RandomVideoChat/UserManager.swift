import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase

class UserManager: ObservableObject {
    static let shared = UserManager()
    private let db = Firestore.firestore()

    @Published var currentUser: User?
    private var recentMatches: Set<String> = []

    private init() {
        loadCurrentUserIfNeeded()
    }

    // MARK: - User Management
    func loadCurrentUserIfNeeded() {
        if let uid = Auth.auth().currentUser?.uid {
            loadCurrentUser(uid: uid)
        }
    }

    func loadCurrentUser(uid: String) {
        db.collection("users").document(uid).getDocument { [weak self] document, error in
            if let error = error {
                AppLogger.user.error("사용자 데이터 로드 실패", error: error)
                return
            }

            if let document = document, document.exists {
                let data = document.data() ?? [:]
                let heartCount = data["heartCount"] as? Int ?? 3
                let blockedUsers = data["blockedUsers"] as? [String] ?? []
                let email = data["email"] as? String
                let displayName = data["displayName"] as? String
                let genderString = data["gender"] as? String ?? ""
                let preferredGenderString = data["preferredGender"] as? String ?? ""

                var user = User(uid: uid, email: email, displayName: displayName)
                user.heartCount = heartCount
                user.blockedUsers = blockedUsers
                user.gender = Gender(rawValue: genderString)
                user.preferredGender = Gender(rawValue: preferredGenderString)
                self?.currentUser = user

                AppLogger.user.info("사용자 데이터 로드 완료: \(heartCount) 하트")
            } else {
                self?.createUserDocument(uid: uid)
            }
        }
    }

    func createUserDocument(uid: String) {
        let userData: [String: Any] = [
            "uid": uid,
            "heartCount": 3,
            "blockedUsers": [],
            "createdAt": Timestamp(date: Date())
        ]

        db.collection("users").document(uid).setData(userData) { [weak self] error in
            if let error = error {
                AppLogger.user.error("사용자 문서 생성 실패", error: error)
            } else {
                let user = User(uid: uid)
                self?.currentUser = user
                AppLogger.user.notice("새 사용자 문서 생성 완료")
            }
        }
    }

    // MARK: - Heart Management
    func updateHeartCount(uid: String, newCount: Int) {
        db.collection("users").document(uid).updateData([
            "heartCount": newCount
        ]) { [weak self] error in
            if let error = error {
                AppLogger.user.error("하트 업데이트 실패", error: error)
            } else {
                AppLogger.user.info("하트 업데이트 성공: \(newCount)개")
                self?.currentUser?.heartCount = newCount
            }
        }
    }

    // MARK: - Heart Notification System
    func sendHeartToOpponent(_ opponentId: String) {
        let ref = Database.database().reference()
            .child("notifications")
            .child(opponentId)
            .child("newHeart")
            .childByAutoId()

        ref.setValue([
            "timestamp": ServerValue.timestamp(),
            "from": Auth.auth().currentUser?.uid ?? "unknown"
        ]) { error, _ in
            if let error = error {
                AppLogger.user.error("하트 알림 전송 실패", error: error)
            } else {
                AppLogger.user.notice("하트 알림 전송 성공 (상대방: \(opponentId))")
            }
        }
    }

    // MARK: - Real-time Heart Observation
    private var heartListener: ListenerRegistration?

    func observeUserHearts(uid: String, completion: @escaping (Int) -> Void) {
        heartListener?.remove()

        heartListener = db.collection("users").document(uid)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot,
                      let data = document.data(),
                      let heartCount = data["heartCount"] as? Int else {
                    if let error = error {
                        AppLogger.user.error("하트 관찰 에러", error: error)
                    }
                    return
                }

                completion(heartCount)
                AppLogger.user.debug("하트 개수 실시간 업데이트: \(heartCount)")
            }
    }

    func stopObservingHearts() {
        heartListener?.remove()
        heartListener = nil
    }

    // MARK: - Block Management
    func blockUser(_ userId: String) {
        guard let currentUid = Auth.auth().currentUser?.uid else { return }

        db.collection("users").document(currentUid).updateData([
            "blockedUsers": FieldValue.arrayUnion([userId])
        ]) { [weak self] error in
            if let error = error {
                AppLogger.user.error("사용자 차단 실패", error: error)
            } else {
                self?.currentUser?.blockedUsers.append(userId)
                AppLogger.user.notice("사용자 차단 완료: \(userId)")
            }
        }
    }

    func unblockUser(_ userId: String) {
        guard let currentUid = Auth.auth().currentUser?.uid else { return }

        db.collection("users").document(currentUid).updateData([
            "blockedUsers": FieldValue.arrayRemove([userId])
        ]) { [weak self] error in
            if let error = error {
                AppLogger.user.error("차단 해제 실패", error: error)
            } else {
                self?.currentUser?.blockedUsers.removeAll { $0 == userId }
                AppLogger.user.notice("사용자 차단 해제: \(userId)")
            }
        }
    }

    func isUserBlocked(_ userId: String) -> Bool {
        return currentUser?.blockedUsers.contains(userId) ?? false
    }

    // MARK: - Matching Validation
    func canMatchWith(_ userId: String) -> Bool {
        // 1. 자기 자신과는 매칭 불가
        if userId == Auth.auth().currentUser?.uid {
            return false
        }

        // 2. 차단된 사용자와는 매칭 불가
        if isUserBlocked(userId) {
            return false
        }

        // 3. 최근 매칭한 사용자와는 매칭 불가 (세션 기반)
        if hasRecentlyMatched(userId) {
            return false
        }

        return true
    }

    // MARK: - Recent Matches (Session-based)
    private static let maxRecentMatches = 5

    func addRecentMatch(_ userId: String) {
        recentMatches.insert(userId)
        AppLogger.user.debug("세션 매칭 기록 추가: \(userId), 총 \(recentMatches.count)명")

        // 최근 5명만 유지 (메모리 관리)
        if recentMatches.count > Self.maxRecentMatches {
            let matchesArray = Array(recentMatches)
            recentMatches = Set(matchesArray.suffix(Self.maxRecentMatches))
        }
    }

    func hasRecentlyMatched(_ userId: String) -> Bool {
        return recentMatches.contains(userId)
    }

    func clearRecentMatches() {
        recentMatches.removeAll()
        AppLogger.user.debug("세션 매칭 기록 초기화")
    }

    func getRecentMatchesCount() -> Int {
        return recentMatches.count
    }

    // MARK: - User Stats
    func getUserStats(completion: @escaping (Int, Int) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(0, 0)
            return
        }

        db.collection("users").document(uid).getDocument { document, error in
            if let data = document?.data() {
                let totalMatches = data["totalMatches"] as? Int ?? 0
                let totalHeartsSent = data["totalHeartsSent"] as? Int ?? 0
                completion(totalMatches, totalHeartsSent)
            } else {
                completion(0, 0)
            }
        }
    }

    func incrementMatchCount() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        db.collection("users").document(uid).updateData([
            "totalMatches": FieldValue.increment(Int64(1)),
            "lastMatchAt": Timestamp(date: Date())
        ]) { error in
            if let error = error {
                AppLogger.user.error("매칭 횟수 증가 실패", error: error)
                return
            }
            AppLogger.user.debug("매칭 횟수 증가")
        }
    }

    // MARK: - Atomic Heart Management
    func changeHeartCount(uid: String, delta: Int) {
        db.collection("users").document(uid).updateData([
            "heartCount": FieldValue.increment(Int64(delta))
        ]) { [weak self] error in
            if let error = error {
                AppLogger.user.error("하트 수 변경 실패", error: error)
            } else {
                if var user = self?.currentUser {
                    user.heartCount += delta
                    self?.currentUser = user
                }
                AppLogger.user.info("하트 수 \(delta > 0 ? "증가" : "감소"): \(delta)")
            }
        }
    }

    // MARK: - Gender Management
    func updateGender(_ gender: Gender) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        db.collection("users").document(uid).updateData([
            "gender": gender.rawValue
        ]) { [weak self] error in
            if let error = error {
                AppLogger.user.error("성별 업데이트 실패", error: error)
            } else {
                self?.currentUser?.gender = gender
                AppLogger.user.info("성별 업데이트 완료: \(gender.displayName)")
            }
        }
    }

    func updatePreferredGender(_ gender: Gender?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let genderValue = gender?.rawValue ?? ""

        db.collection("users").document(uid).updateData([
            "preferredGender": genderValue
        ]) { [weak self] error in
            if let error = error {
                AppLogger.user.error("선호 성별 업데이트 실패", error: error)
            } else {
                self?.currentUser?.preferredGender = gender
                if let gender = gender {
                    AppLogger.user.info("선호 성별 업데이트 완료: \(gender.displayName)")
                } else {
                    AppLogger.user.info("선호 성별 선택 해제 완료")
                }
            }
        }
    }

    // MARK: - Content Safety
    func checkContentSafety(completion: @escaping (Bool, String?) -> Void) {
        // 기본적으로 허용
        completion(true, nil)
    }
}
