import SwiftUI
import AgoraRtcKit
import AVFoundation

// MARK: - Agora Manager
/// Agora RTC 엔진을 관리하는 싱글톤 매니저
/// - 실시간 영상/음성 통화 관리
/// - 토큰 기반 인증 및 자동 갱신
/// - 네트워크 상태에 따른 적응형 비디오 품질
/// - 연결 상태 모니터링 및 자동 재연결
final class AgoraManager: NSObject, ObservableObject {
    static let shared = AgoraManager()

    // Agora 설정 - Info.plist에서 안전하게 가져오기
    private let appId: String = {
        guard let appId = Bundle.main.object(forInfoDictionaryKey: "AGORA_APP_ID") as? String,
              !appId.isEmpty else {
            fatalError("AGORA_APP_ID가 Info.plist에서 찾을 수 없습니다.")
        }
        return appId
    }()
    private var agoraKit: AgoraRtcEngineKit?

    // 상태 관리
    @Published var isInCall = false
    @Published var remoteUserJoined = false
    @Published var remoteVideoEnabled = false
    @Published var localVideoView: UIView?
    @Published var remoteVideoView: UIView?
    @Published var connectionError: String?

    // 사용자 정보
    var localUserId: UInt = 0
    var remoteUserId: UInt = 0
    var channelName: String = ""

    // 토큰 관리
    private var currentToken: String?
    private let tokenService = AgoraTokenService.shared

    // 재연결 관리
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var isReconnecting = false

    // 오디오/비디오 상태
    private var isMuted = false
    @Published var isCameraOff = false

    override init() {
        super.init()
        setupAgoraEngine()
        setupTokenRefreshObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        tokenService.clearCache()
    }

    // MARK: - Token Refresh Observer
    private func setupTokenRefreshObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTokenRefreshed(_:)),
            name: .agoraTokenRefreshed,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTokenRefreshFailed),
            name: .agoraTokenRefreshFailed,
            object: nil
        )
    }

    @objc private func handleTokenRefreshed(_ notification: Notification) {
        guard let token = notification.userInfo?["token"] as? String else { return }
        AppLogger.agora.info("토큰 갱신됨 - Agora에 새 토큰 적용")
        currentToken = token
        agoraKit?.renewToken(token)
    }

    @objc private func handleTokenRefreshFailed() {
        AppLogger.agora.error("토큰 갱신 실패 - 통화 종료 필요")
        DispatchQueue.main.async {
            self.connectionError = "인증이 만료되었습니다. 다시 연결해주세요."
        }
    }

    // MARK: - Agora 엔진 설정
    private func setupAgoraEngine() {
        AppLogger.agora.info("Agora 엔진 초기화 시작")

        // 엔진 초기화
        let config = AgoraRtcEngineConfig()
        config.appId = appId
        config.channelProfile = .communication

        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)

        // 성능 최적화 설정
        setupPerformanceOptimizations()

        guard agoraKit != nil else {
            AppLogger.agora.error("Agora 엔진 초기화 실패")
            return
        }

        AppLogger.agora.notice("Agora 엔진 초기화 성공")

        // 클라이언트 역할 설정
        agoraKit?.setClientRole(.broadcaster)

        // 기본 오디오 라우트 설정
        agoraKit?.setDefaultAudioRouteToSpeakerphone(true)

        // 비디오/오디오 활성화
        agoraKit?.enableVideo()
        agoraKit?.enableAudio()
        agoraKit?.enableLocalVideo(true)
        agoraKit?.enableLocalAudio(true)

        // 비디오 설정
        let videoConfig = AgoraVideoEncoderConfiguration(
            size: AgoraVideoDimension640x480,
            frameRate: .fps30,
            bitrate: AgoraVideoBitrateStandard,
            orientationMode: .adaptative,
            mirrorMode: .auto
        )
        agoraKit?.setVideoEncoderConfiguration(videoConfig)

        // 로컬 비디오 뷰 설정
        setupLocalVideo()

        AppLogger.agora.debug("Agora 엔진 설정 완료")
    }

    // MARK: - 로컬 비디오 설정
    private func setupLocalVideo() {
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = 0
        videoCanvas.renderMode = .hidden

        let view = UIView()
        videoCanvas.view = view

        agoraKit?.setupLocalVideo(videoCanvas)
        agoraKit?.startPreview()

        DispatchQueue.main.async {
            self.localVideoView = view
        }

        AppLogger.agora.debug("로컬 비디오 설정 완료")
    }

    // MARK: - 통화 시작 (토큰 서버 연동)
    func startCall(channel: String) {
        AppLogger.agora.info("startCall - 채널: \(channel)")

        // 채널 이름 유효성 검사
        guard channel.count <= 64 && !channel.isEmpty else {
            AppLogger.agora.error("유효하지 않은 채널 이름: \(channel.count)자")
            DispatchQueue.main.async {
                self.connectionError = "유효하지 않은 채널 이름입니다."
            }
            return
        }

        // 엔진 상태 확인
        guard agoraKit != nil else {
            AppLogger.agora.warning("Agora 엔진 미초기화 - 재초기화 시도")
            setupAgoraEngine()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startCall(channel: channel)
            }
            return
        }

        self.channelName = channel
        reconnectAttempts = 0
        isReconnecting = false

        // 토큰 요청 후 채널 참가
        AppLogger.agora.debug("토큰 요청 중...")
        tokenService.generateToken(channelName: channel, uid: 0) { [weak self] result in
            switch result {
            case .success(let response):
                AppLogger.agora.notice("토큰 획득 성공")
                self?.currentToken = response.token
                self?.joinChannelWithToken(channel: channel, token: response.token)

            case .failure(let error):
                AppLogger.agora.error("토큰 획득 실패", error: error)
                #if DEBUG
                AppLogger.agora.warning("DEBUG 모드: 토큰 없이 연결 시도")
                self?.joinChannelWithToken(channel: channel, token: nil)
                #else
                DispatchQueue.main.async {
                    self?.connectionError = error.localizedDescription
                }
                #endif
            }
        }
    }

    /// 토큰과 함께 채널 참가
    private func joinChannelWithToken(channel: String, token: String?) {
        guard let engine = agoraKit else {
            AppLogger.agora.error("Agora 엔진 없음")
            return
        }

        AppLogger.agora.debug("joinChannel 호출 - 토큰: \(token != nil ? "있음" : "없음")")

        // 채널 참가 옵션 설정
        let options = AgoraRtcChannelMediaOptions()
        options.publishCameraTrack = true
        options.publishMicrophoneTrack = true
        options.clientRoleType = .broadcaster
        options.autoSubscribeVideo = true
        options.autoSubscribeAudio = true
        options.channelProfile = .communication

        // 채널 참가
        let result = engine.joinChannel(
            byToken: token,
            channelId: channel,
            uid: 0,
            mediaOptions: options
        ) { [weak self] channel, uid, elapsed in
            AppLogger.agora.notice("채널 참가 성공: \(channel), uid: \(uid), elapsed: \(elapsed)ms")
            self?.localUserId = uid
            self?.reconnectAttempts = 0
            self?.isReconnecting = false
            DispatchQueue.main.async {
                self?.isInCall = true
                self?.connectionError = nil
            }
        }

        if result != 0 {
            AppLogger.agora.error("joinChannel 실패: \(result)")
            handleJoinError(result)
        } else {
            AppLogger.agora.debug("joinChannel 호출 성공")
        }
    }

    /// 재연결 시도
    private func attemptReconnect() {
        guard !isReconnecting else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            AppLogger.agora.error("최대 재연결 시도 횟수 초과")
            DispatchQueue.main.async {
                self.connectionError = "연결에 실패했습니다. 다시 시도해주세요."
            }
            return
        }

        isReconnecting = true
        reconnectAttempts += 1
        let delay = TimeInterval(reconnectAttempts * 2)

        AppLogger.agora.info("재연결 시도 \(reconnectAttempts)/\(maxReconnectAttempts) - \(delay)초 후")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.channelName.isEmpty else { return }
            self.isReconnecting = false
            self.startCall(channel: self.channelName)
        }
    }

    // MARK: - 에러 처리
    private func handleJoinError(_ errorCode: Int32) {
        let message: String
        switch errorCode {
        case -2: message = "잘못된 매개변수"
        case -3: message = "SDK 초기화 실패"
        case -7: message = "SDK 초기화되지 않음"
        case -17: message = "이미 채널에 참가중"
        default: message = "알 수 없는 에러: \(errorCode)"
        }
        AppLogger.agora.error(message)
    }

    // MARK: - 통화 종료
    func endCall() {
        AppLogger.agora.info("통화 종료")
        agoraKit?.leaveChannel(nil)
        agoraKit?.stopPreview()

        tokenService.clearCache()
        currentToken = nil

        DispatchQueue.main.async {
            self.isInCall = false
            self.remoteUserJoined = false
            self.remoteVideoEnabled = false
            self.remoteUserId = 0
            self.channelName = ""
            self.connectionError = nil
            self.reconnectAttempts = 0
            self.isReconnecting = false
        }
    }

    // MARK: - 음소거 토글
    func toggleMute() -> Bool {
        isMuted.toggle()
        agoraKit?.muteLocalAudioStream(isMuted)
        AppLogger.agora.debug("음소거: \(isMuted)")
        return isMuted
    }

    // MARK: - 카메라 전환
    func switchCamera() {
        agoraKit?.switchCamera()
        AppLogger.agora.debug("카메라 전환")
    }

    // MARK: - 카메라 토글
    func toggleCamera() -> Bool {
        isCameraOff.toggle()
        agoraKit?.muteLocalVideoStream(isCameraOff)
        AppLogger.agora.debug("카메라: \(isCameraOff ? "OFF" : "ON")")
        return isCameraOff
    }
}

// MARK: - Agora Delegate
extension AgoraManager: AgoraRtcEngineDelegate {

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        AppLogger.agora.notice("didJoinChannel - 채널: \(channel), UID: \(uid), 소요시간: \(elapsed)ms")
        localUserId = uid
        DispatchQueue.main.async {
            self.isInCall = true
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        AppLogger.agora.info("원격 사용자 참가: \(uid)")

        remoteUserId = uid

        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        videoCanvas.renderMode = .hidden

        let view = UIView()
        videoCanvas.view = view

        agoraKit?.setupRemoteVideo(videoCanvas)

        DispatchQueue.main.async {
            self.remoteVideoView = view
            self.remoteUserJoined = true
            self.remoteVideoEnabled = true
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        AppLogger.agora.info("원격 사용자 오프라인: \(uid), 이유: \(reason.rawValue)")

        if reason == .dropped {
            MatchingManager.shared.signalCallEnd()
        }

        DispatchQueue.main.async {
            self.remoteUserJoined = false
            self.remoteVideoEnabled = false
            self.remoteVideoView = nil
            self.remoteUserId = 0
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, connectionChangedTo state: AgoraConnectionState, reason: AgoraConnectionChangedReason) {
        AppLogger.agora.debug("연결 상태 변경: \(state.rawValue), 이유: \(reason.rawValue)")

        switch state {
        case .disconnected:
            if reason != .leaveChannel && !channelName.isEmpty {
                attemptReconnect()
            }

        case .connecting:
            AppLogger.agora.debug("연결 중...")

        case .connected:
            AppLogger.agora.notice("연결됨")
            reconnectAttempts = 0
            isReconnecting = false
            DispatchQueue.main.async {
                self.connectionError = nil
            }

        case .reconnecting:
            AppLogger.agora.debug("재연결 중...")

        case .failed:
            AppLogger.agora.error("연결 실패 - 원인: \(reason.rawValue)")

            if reason == .tokenExpired {
                AppLogger.agora.info("토큰 만료 - 갱신 시도")
                tokenService.refreshToken(channelName: channelName, uid: localUserId) { [weak self] result in
                    switch result {
                    case .success(let response):
                        self?.currentToken = response.token
                        self?.agoraKit?.renewToken(response.token)
                    case .failure:
                        self?.attemptReconnect()
                    }
                }
            } else {
                attemptReconnect()
            }

        @unknown default:
            break
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, tokenPrivilegeWillExpire token: String) {
        AppLogger.agora.warning("토큰 곧 만료 - 갱신 요청")
        tokenService.refreshToken(channelName: channelName, uid: localUserId) { [weak self] result in
            if case .success(let response) = result {
                self?.currentToken = response.token
                self?.agoraKit?.renewToken(response.token)
                AppLogger.agora.notice("토큰 갱신 완료")
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        AppLogger.agora.error("Agora 에러: \(errorCode.rawValue)")
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        AppLogger.agora.warning("Agora 경고: \(warningCode.rawValue)")
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, remoteVideoStateChangedOfUid uid: UInt, state: AgoraVideoRemoteState, reason: AgoraVideoRemoteReason, elapsed: Int) {
        AppLogger.agora.debug("원격 비디오 상태 변경: UID \(uid), 상태: \(state.rawValue)")

        DispatchQueue.main.async {
            switch state {
            case .stopped, .frozen:
                self.remoteVideoEnabled = false
            case .starting, .decoding:
                self.remoteVideoEnabled = true
            @unknown default:
                break
            }
        }
    }

    // MARK: - Performance Optimizations
    private func setupPerformanceOptimizations() {
        guard let agoraKit = agoraKit else { return }

        setupAdaptiveVideoConfig()

        agoraKit.setAudioProfile(.speechStandard, scenario: .default)
        agoraKit.enableAudio()
        agoraKit.enableVideo()
        agoraKit.setEnableSpeakerphone(true)
        agoraKit.enableDualStreamMode(true)

        AppLogger.agora.debug("Agora 성능 최적화 설정 완료")
    }

    private func setupAdaptiveVideoConfig() {
        guard let agoraKit = agoraKit else { return }

        let videoConfig = AgoraVideoEncoderConfiguration()
        let networkQuality = PerformanceMonitor.shared.getNetworkQuality()

        switch networkQuality {
        case .excellent:
            videoConfig.dimensions = AgoraVideoDimension960x720
            videoConfig.frameRate = .fps30
            videoConfig.bitrate = 1130

        case .good:
            videoConfig.dimensions = AgoraVideoDimension640x480
            videoConfig.frameRate = .fps24
            videoConfig.bitrate = 800

        case .poor:
            videoConfig.dimensions = AgoraVideoDimension320x240
            videoConfig.frameRate = .fps15
            videoConfig.bitrate = 200

        default:
            videoConfig.dimensions = AgoraVideoDimension640x480
            videoConfig.frameRate = .fps24
            videoConfig.bitrate = AgoraVideoBitrateStandard
        }

        videoConfig.mirrorMode = .disabled
        agoraKit.setVideoEncoderConfiguration(videoConfig)

        AppLogger.agora.debug("비디오 설정 적용: \(networkQuality.description)")
    }

    func adaptVideoQualityToNetwork() {
        setupAdaptiveVideoConfig()
    }

    func collectPerformanceMetrics() {
        AppLogger.performance.debug("Agora 상태 - remoteUser: \(remoteUserJoined), video: \(remoteVideoEnabled), inCall: \(isInCall)")
    }
}
