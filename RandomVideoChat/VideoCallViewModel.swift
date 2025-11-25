import SwiftUI
import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase

// MARK: - VideoCallViewModel
/// 비디오 통화의 비즈니스 로직을 관리하는 ViewModel
@available(iOS 15.0, *)
final class VideoCallViewModel: ObservableObject {

    // MARK: - Published Properties
    @Published var isCallActive = false
    @Published var timeRemaining = 5
    @Published var isTimerStarted = false
    @Published var isMuted = false
    @Published var heartCount = 3
    @Published var isCallEnding = false
    @Published var opponentUserId: String = ""
    @Published var showHeartAnimation = false
    @Published var isCameraOn = true
    @Published var heartCountAnimation = false

    // MARK: - Alert States
    @Published var showReportAlert = false
    @Published var showBlockAlert = false
    @Published var reportReason = ""

    // MARK: - Background State
    @Published var isBackground = false

    // MARK: - Private Properties
    private var timer: Timer?
    private var backgroundTerminationWorkItem: DispatchWorkItem?
    private let userManager = UserManager.shared
    private let agoraManager = AgoraManager.shared
    private let matchingManager = MatchingManager.shared
    private var heartCountListener: ListenerRegistration?

    // MARK: - Initialization
    init() {
        AppLogger.matching.debug("VideoCallViewModel 초기화")
    }

    deinit {
        cleanup()
        AppLogger.matching.debug("VideoCallViewModel 메모리 해제")
    }

    // MARK: - Public Methods

    /// 비디오 통화 설정 및 시작
    func setupVideoCall() {
        setupCameraState()
        startVideoCall()
        setupUserData()
        setupOpponentObservation()
        setupCallObservers()
    }

    /// 비디오 통화 종료
    func endVideoCall(dismiss: @escaping () -> Void) {
        cleanupAfterCallEnd(signalEnd: true)
        dismiss()
    }

    /// 마이크 음소거 토글
    func toggleMute() {
        isMuted = agoraManager.toggleMute()
    }

    /// 카메라 전환
    func switchCamera() {
        agoraManager.switchCamera()
    }

    /// 카메라 On/Off 토글
    func toggleCamera() {
        let isCameraOff = agoraManager.toggleCamera()
        isCameraOn = !isCameraOff
        UserDefaults.standard.set(isCameraOn, forKey: "isCameraOn")
    }

    /// +60초 버튼 액션
    func addTime() {
        guard heartCount > 0, !opponentUserId.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // 애니메이션 트리거
        withAnimation {
            heartCountAnimation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.heartCountAnimation = false
        }

        // UI 즉시 업데이트
        heartCount -= 1
        UserDefaults.standard.set(heartCount, forKey: "heartCount")

        // 타이머 +60초
        timeRemaining += 60
        matchingManager.updateCallTimer(timeRemaining)

        // 서버에 원자적으로 하트 감소
        userManager.changeHeartCount(uid: uid, delta: -1)

        // 상대방에게 하트 알림 전송
        userManager.sendHeartToOpponent(opponentUserId)

        if isTimerStarted {
            startTimer()
        }
    }

    /// 사용자 신고
    func reportUser(reason: String, completion: @escaping () -> Void) {
        guard !opponentUserId.isEmpty else {
            AppLogger.moderation.warning("신고 실패: 상대방 ID가 없음")
            return
        }

        ContentModerationManager.shared.reportUser(reportedUserId: opponentUserId, reason: reason) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    AppLogger.moderation.notice("신고 완료: \(reason)")
                    self?.cleanupAfterCallEnd(signalEnd: true)
                    completion()
                } else {
                    AppLogger.moderation.error("신고 실패")
                }
            }
        }
    }

    /// 사용자 차단
    func blockUser(completion: @escaping () -> Void) {
        guard !opponentUserId.isEmpty else {
            AppLogger.moderation.warning("차단 실패: 상대방 ID가 없음")
            return
        }

        userManager.reportAndBlockUser(opponentUserId, reason: "사용자 차단")
        AppLogger.moderation.notice("사용자 신고 및 차단: \(opponentUserId)")

        cleanupAfterCallEnd(signalEnd: true)
        completion()
    }

    // MARK: - Scene Phase Handling

    /// 앱 상태 변화 처리
    func handleScenePhaseChange(_ newPhase: ScenePhase, dismiss: @escaping () -> Void) {
        if newPhase == .background || newPhase == .inactive {
            isBackground = true

            // 기존 타이머가 있다면 취소 후 새로 시작
            backgroundTerminationWorkItem?.cancel()

            // 5초 후 통화 종료를 예약
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.isBackground && !self.isCallEnding {
                    self.cleanupAfterCallEnd(signalEnd: true)
                    dismiss()
                }
            }
            backgroundTerminationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)

        } else if newPhase == .active {
            // 앱이 다시 활성화되면 예약된 작업 취소
            isBackground = false
            backgroundTerminationWorkItem?.cancel()
            backgroundTerminationWorkItem = nil
        }
    }

    /// 앱 종료 처리
    func handleAppTermination() {
        guard !isCallEnding else { return }
        cleanupAfterCallEnd(signalEnd: true)
    }

    /// onDisappear 처리
    func handleDisappear() {
        // 백그라운드로 이동했다면 즉시 종료하지 않음
        if isBackground {
            return
        }
        cleanupAfterCallEnd(signalEnd: true)
    }

    /// 원격 사용자 참가 시 타이머 시작
    func handleRemoteUserJoined() {
        if !isTimerStarted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startTimer()
            }
        }
    }

    // MARK: - Private Methods

    private func setupCameraState() {
        // 메인화면에서 설정한 카메라 상태 복원
        isCameraOn = UserDefaults.standard.bool(forKey: "isCameraOn")
        // 기본값이 false이므로 한번도 설정하지 않았다면 true로 설정
        if UserDefaults.standard.object(forKey: "isCameraOn") == nil {
            isCameraOn = true
            UserDefaults.standard.set(true, forKey: "isCameraOn")
        }

        // Agora 카메라 상태도 동기화
        if !isCameraOn {
            _ = agoraManager.toggleCamera()
        }
    }

    private func setupUserData() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        userManager.loadCurrentUser(uid: uid)
        observeHeartCount(uid: uid)
        observeNewHeartNotification()

        if let currentHeartCount = userManager.currentUser?.heartCount {
            heartCount = currentHeartCount
        }
    }

    private func setupOpponentObservation() {
        guard let matchedUserId = matchingManager.matchedUserId else { return }

        opponentUserId = matchedUserId
        userManager.addRecentMatch(matchedUserId)

        // 상대방 presence 감시 시작
        matchingManager.observeOpponentPresence(opponentId: matchedUserId) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard !self.isCallEnding && !self.isBackground else { return }
                self.cleanupAfterCallEnd(signalEnd: false)
            }
        }
    }

    private func setupCallObservers() {
        // 타이머 동기화 관찰
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.matchingManager.observeCallTimer { [weak self] syncedTime in
                guard let self = self else { return }
                if syncedTime > self.timeRemaining {
                    self.timeRemaining = syncedTime
                    if self.isTimerStarted {
                        self.startTimer()
                    }
                }
            }
        }

        // 통화 종료 관찰 등록 함수 정의
        func registerCallEndObserver() {
            if let matchId = UserDefaults.standard.string(forKey: "currentMatchId"), !matchId.isEmpty {
                // endedBy 필드 기반 관찰
                self.matchingManager.observeCallEnd { [weak self] in
                    guard let self = self, !self.isCallEnding else { return }
                    self.cleanupAfterCallEnd(signalEnd: false)
                }
                // status 필드 기반 관찰 (이중 안전장치)
                self.matchingManager.observeCallStatusEnded { [weak self] in
                    guard let self = self, !self.isCallEnding else { return }
                    self.cleanupAfterCallEnd(signalEnd: false)
                }
            } else {
                // matchId가 없으면 0.3초 후 재시도
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    registerCallEndObserver()
                }
            }
        }

        // 옵저버 등록 시작
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            registerCallEndObserver()
        }
    }

    private func startVideoCall() {
        isCallActive = true
        if let channelName = UserDefaults.standard.string(forKey: "currentChannelName") {
            agoraManager.startCall(channel: channelName)
        }
    }

    private func startTimer() {
        // 기존 타이머 정리
        timer?.invalidate()
        timer = nil

        isTimerStarted = true

        // 타이머 생성
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] currentTimer in
            guard let self = self else {
                currentTimer.invalidate()
                return
            }

            // 통화 종료 중이면 타이머 중지
            guard !self.isCallEnding else {
                currentTimer.invalidate()
                return
            }

            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                currentTimer.invalidate()
                self.cleanupAfterCallEnd(signalEnd: true)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isTimerStarted = false
    }

    // MARK: - Heart Observation

    private func observeHeartCount(uid: String) {
        let db = Firestore.firestore()
        heartCountListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self, let document = documentSnapshot else { return }
                if let data = document.data(),
                   let newHeartCount = data["heartCount"] as? Int {
                    if newHeartCount != self.heartCount {
                        DispatchQueue.main.async {
                            self.heartCount = newHeartCount
                            UserDefaults.standard.set(newHeartCount, forKey: "heartCount")
                        }
                    }
                }
            }
    }

    private func observeNewHeartNotification() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Database.database().reference()
            .child("notifications")
            .child(uid)
            .child("newHeart")
            .observe(.childAdded) { [weak self] snapshot in
                guard let self = self else { return }

                // 로컬 UI에서 즉시 반영
                DispatchQueue.main.async {
                    self.heartCount += 1
                    UserDefaults.standard.set(self.heartCount, forKey: "heartCount")
                }

                // 서버에 +1 원자적 증가
                self.userManager.changeHeartCount(uid: uid, delta: +1)

                // 알림 데이터 삭제
                snapshot.ref.removeValue()
            }
    }

    // MARK: - Cleanup

    private func cleanupAfterCallEnd(signalEnd: Bool) {
        guard !isCallEnding else { return }

        isCallEnding = true

        // 예약된 백그라운드 작업 취소
        backgroundTerminationWorkItem?.cancel()
        backgroundTerminationWorkItem = nil

        if signalEnd {
            // 내가 종료하는 경우에만 통화 종료 신호 전송 (matchId 삭제 전에 실행)
            if let matchId = UserDefaults.standard.string(forKey: "currentMatchId") {
                matchingManager.signalCallEnd(matchId: matchId)
                AppLogger.matching.debug("통화 종료 신호 전송 시도: matchId = \(matchId)")
            } else {
                AppLogger.matching.warning("통화 종료 신호 전송 실패: matchId가 없음")
                matchingManager.signalCallEnd()
            }
        }

        // 매칭 상태를 항상 초기화 (signalEnd 후에 실행하여 matchId 삭제)
        matchingManager.cancelMatching()

        if !signalEnd {
            // 상대방이 종료한 경우 MATCHED! 플래시 방지를 위해 플래그 설정
            matchingManager.callEndedByOpponent = true
        }

        // 타이머 정리
        stopTimer()

        // Agora 연결 종료
        agoraManager.endCall()

        // Firebase 리스너 정리
        matchingManager.cleanupCallObservers()
        heartCountListener?.remove()
        heartCountListener = nil

        // UserDefaults 정리
        UserDefaults.standard.removeObject(forKey: "currentChannelName")
        UserDefaults.standard.removeObject(forKey: "currentMatchId")
    }

    private func cleanup() {
        stopTimer()
        backgroundTerminationWorkItem?.cancel()
        backgroundTerminationWorkItem = nil
        heartCountListener?.remove()
        heartCountListener = nil
    }
}
