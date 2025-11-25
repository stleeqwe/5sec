import Foundation
import FirebaseDatabase
import FirebaseFirestore

// MARK: - Firebase Listener Manager
/// Firebase 리스너들을 중앙에서 관리하는 매니저
/// 메모리 누수 방지 및 리스너 정리를 자동화
final class FirebaseListenerManager {
    static let shared = FirebaseListenerManager()

    // MARK: - Listener Storage
    private var realtimeListeners: [String: DatabaseHandle] = [:]
    private var firestoreListeners: [String: ListenerRegistration] = [:]
    private let queue = DispatchQueue(label: "firebase.listener.queue", attributes: .concurrent)

    private init() {
        AppLogger.firebase.debug("FirebaseListenerManager 초기화")
    }

    deinit {
        removeAllListeners()
    }

    // MARK: - Realtime Database Listeners

    /// Realtime Database 리스너 추가
    /// - Parameters:
    ///   - key: 리스너 식별자
    ///   - reference: Firebase 레퍼런스
    ///   - eventType: 이벤트 타입
    ///   - handler: 이벤트 핸들러
    func addRealtimeListener(
        key: String,
        reference: DatabaseReference,
        eventType: DataEventType,
        handler: @escaping (DataSnapshot) -> Void
    ) {
        // 기존 리스너 제거
        removeRealtimeListener(key: key)

        let handle = reference.observe(eventType) { snapshot in
            handler(snapshot)
        }

        queue.async(flags: .barrier) {
            self.realtimeListeners[key] = handle
        }

        AppLogger.firebase.debug("Realtime 리스너 추가: \(key)")
    }

    /// Realtime Database 리스너 제거
    func removeRealtimeListener(key: String) {
        queue.async(flags: .barrier) {
            guard let handle = self.realtimeListeners.removeValue(forKey: key) else { return }
            Database.database().reference().removeObserver(withHandle: handle)
            AppLogger.firebase.debug("Realtime 리스너 제거: \(key)")
        }
    }

    // MARK: - Firestore Listeners

    /// Firestore 리스너 추가
    /// - Parameters:
    ///   - key: 리스너 식별자
    ///   - listener: Firestore 리스너 등록 객체
    func addFirestoreListener(key: String, listener: ListenerRegistration) {
        // 기존 리스너 제거
        removeFirestoreListener(key: key)

        queue.async(flags: .barrier) {
            self.firestoreListeners[key] = listener
        }

        AppLogger.firebase.debug("Firestore 리스너 추가: \(key)")
    }

    /// Firestore 리스너 제거
    func removeFirestoreListener(key: String) {
        queue.async(flags: .barrier) {
            guard let listener = self.firestoreListeners.removeValue(forKey: key) else { return }
            listener.remove()
            AppLogger.firebase.debug("Firestore 리스너 제거: \(key)")
        }
    }

    // MARK: - Bulk Operations

    /// 특정 프리픽스로 시작하는 모든 리스너 제거
    func removeListeners(withPrefix prefix: String) {
        queue.async(flags: .barrier) {
            // Realtime listeners
            let realtimeKeys = self.realtimeListeners.keys.filter { $0.hasPrefix(prefix) }
            for key in realtimeKeys {
                if let handle = self.realtimeListeners.removeValue(forKey: key) {
                    Database.database().reference().removeObserver(withHandle: handle)
                }
            }

            // Firestore listeners
            let firestoreKeys = self.firestoreListeners.keys.filter { $0.hasPrefix(prefix) }
            for key in firestoreKeys {
                if let listener = self.firestoreListeners.removeValue(forKey: key) {
                    listener.remove()
                }
            }

            if !realtimeKeys.isEmpty || !firestoreKeys.isEmpty {
                AppLogger.firebase.debug("프리픽스 '\(prefix)' 리스너 제거: Realtime=\(realtimeKeys.count), Firestore=\(firestoreKeys.count)")
            }
        }
    }

    /// 모든 리스너 제거
    func removeAllListeners() {
        queue.async(flags: .barrier) {
            // Realtime listeners
            for (key, handle) in self.realtimeListeners {
                Database.database().reference().removeObserver(withHandle: handle)
                AppLogger.firebase.debug("Realtime 리스너 제거: \(key)")
            }
            self.realtimeListeners.removeAll()

            // Firestore listeners
            for (key, listener) in self.firestoreListeners {
                listener.remove()
                AppLogger.firebase.debug("Firestore 리스너 제거: \(key)")
            }
            self.firestoreListeners.removeAll()

            AppLogger.firebase.notice("모든 Firebase 리스너 제거 완료")
        }
    }

    // MARK: - Status

    /// 현재 활성 리스너 개수
    var activeListenerCount: Int {
        var count = 0
        queue.sync {
            count = realtimeListeners.count + firestoreListeners.count
        }
        return count
    }

    /// 디버그용 리스너 상태 출력
    func logStatus() {
        queue.sync {
            AppLogger.firebase.debug("""
            Firebase Listener Status:
            - Realtime: \(realtimeListeners.count) [\(realtimeListeners.keys.joined(separator: ", "))]
            - Firestore: \(firestoreListeners.count) [\(firestoreListeners.keys.joined(separator: ", "))]
            """)
        }
    }
}

// MARK: - Listener Keys
/// 리스너 키 상수
enum ListenerKey {
    // Matching
    static let matchingQueue = "matching.queue"
    static let matchingStatus = "matching.status"
    static let matchingTimer = "matching.timer"

    // Call
    static let callEnd = "call.end"
    static let callStatus = "call.status"
    static let callPresence = "call.presence"

    // User
    static let userHeart = "user.heart"
    static let userNotification = "user.notification"

    // Prefix for call-related listeners
    static let callPrefix = "call."
    static let matchingPrefix = "matching."
}
