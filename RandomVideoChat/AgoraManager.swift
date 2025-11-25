import SwiftUI
import AgoraRtcKit
import AVFoundation

class AgoraManager: NSObject, ObservableObject {
    static let shared = AgoraManager()

    // Agora 설정 - Info.plist에서 안전하게 가져오기
    private let appId: String = {
        guard let appId = Bundle.main.object(forInfoDictionaryKey: "AGORA_APP_ID") as? String,
              !appId.isEmpty else {
            fatalError("⚠️ AGORA_APP_ID가 Info.plist에서 찾을 수 없습니다. 앱을 실행할 수 없습니다.")
        }
        return appId
    }()
    private var agoraKit: AgoraRtcEngineKit?

    // 상태 관리
    @Published var isInCall = false
    @Published var remoteUserJoined = false
    @Published var remoteVideoEnabled = false  // 초기값을 false로 변경
    @Published var localVideoView: UIView?
    @Published var remoteVideoView: UIView?
    @Published var connectionError: String?  // 연결 에러 메시지

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
        print("🔄 토큰 갱신됨 - Agora에 새 토큰 적용")
        currentToken = token
        agoraKit?.renewToken(token)
    }

    @objc private func handleTokenRefreshFailed() {
        print("❌ 토큰 갱신 실패 - 통화 종료 필요")
        DispatchQueue.main.async {
            self.connectionError = "인증이 만료되었습니다. 다시 연결해주세요."
        }
    }
    
    // MARK: - Agora 엔진 설정
    private func setupAgoraEngine() {
        print("🔧 Agora 엔진 초기화 시작")
        print("📱 App ID: \(appId)")  // 🆕 App ID 확인
        
        // 엔진 초기화
        let config = AgoraRtcEngineConfig()
        config.appId = appId
        config.channelProfile = .communication  // 1:1 통화용
        
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        
        // 성능 최적화 설정
        setupPerformanceOptimizations()
        
        guard agoraKit != nil else {
            print("❌ Agora 엔진 초기화 실패!")
            return
        }
        
        print("✅ Agora 엔진 초기화 성공")
        
        // 🆕 중요: 클라이언트 역할을 명시적으로 설정
        agoraKit?.setClientRole(.broadcaster)
        print("✅ 클라이언트 역할: broadcaster")
        
        // 🆕 중요: 기본 오디오 라우트 설정
        agoraKit?.setDefaultAudioRouteToSpeakerphone(true)
        print("✅ 스피커폰 설정")
        
        // 비디오 활성화
        agoraKit?.enableVideo()
        print("✅ 비디오 활성화")
        
        // 오디오 활성화
        agoraKit?.enableAudio()
        print("✅ 오디오 활성화")
        
        // 🆕 중요: 로컬 오디오/비디오 명시적 활성화
        agoraKit?.enableLocalVideo(true)
        agoraKit?.enableLocalAudio(true)
        print("✅ 로컬 미디어 활성화")
        
        // 비디오 설정
        let videoConfig = AgoraVideoEncoderConfiguration(
            size: AgoraVideoDimension640x480,
            frameRate: .fps30,
            bitrate: AgoraVideoBitrateStandard,
            orientationMode: .adaptative,
            mirrorMode: .auto
        )
        agoraKit?.setVideoEncoderConfiguration(videoConfig)
        print("✅ 비디오 설정 완료")
        
        // 로컬 비디오 뷰 설정
        setupLocalVideo()
    }
    
    // MARK: - 로컬 비디오 설정
    private func setupLocalVideo() {
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = 0
        videoCanvas.renderMode = .hidden
        
        // 로컬 비디오 뷰 생성
        let view = UIView()
        videoCanvas.view = view
        
        agoraKit?.setupLocalVideo(videoCanvas)
        agoraKit?.startPreview()
        
        DispatchQueue.main.async {
            self.localVideoView = view
        }
        
        print("✅ 로컬 비디오 설정 완료")
    }
    
    // MARK: - 통화 시작 (토큰 서버 연동)
    func startCall(channel: String) {
        print("📱 AgoraManager: startCall - 채널: \(channel)")
        print("📱 채널 길이: \(channel.count) (최대 64자)")

        // 채널 이름 유효성 검사
        guard channel.count <= 64 && !channel.isEmpty else {
            print("❌ 유효하지 않은 채널 이름! (\(channel.count)자)")
            DispatchQueue.main.async {
                self.connectionError = "유효하지 않은 채널 이름입니다."
            }
            return
        }

        // 엔진 상태 확인
        guard agoraKit != nil else {
            print("❌ Agora 엔진이 초기화되지 않았습니다")
            setupAgoraEngine()

            // 재시도
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startCall(channel: channel)
            }
            return
        }

        self.channelName = channel
        reconnectAttempts = 0
        isReconnecting = false

        // 토큰 요청 후 채널 참가
        print("🔑 토큰 요청 중...")
        tokenService.generateToken(channelName: channel, uid: 0) { [weak self] result in
            switch result {
            case .success(let response):
                print("✅ 토큰 획득 성공")
                self?.currentToken = response.token
                self?.joinChannelWithToken(channel: channel, token: response.token)

            case .failure(let error):
                print("❌ 토큰 획득 실패: \(error.localizedDescription)")
                // 토큰 서버 실패 시 토큰 없이 시도 (개발/테스트 모드용)
                #if DEBUG
                print("⚠️ DEBUG 모드: 토큰 없이 연결 시도")
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
            print("❌ Agora 엔진 없음")
            return
        }

        print("🎯 joinChannel 호출 - 토큰: \(token != nil ? "있음" : "없음")")

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
            print("✅ joinChannel 콜백 호출됨!")
            print("✅ 채널 참가 성공: \(channel), uid: \(uid), elapsed: \(elapsed)ms")
            self?.localUserId = uid
            self?.reconnectAttempts = 0
            self?.isReconnecting = false
            DispatchQueue.main.async {
                self?.isInCall = true
                self?.connectionError = nil
            }
        }

        print("🎯 joinChannel 호출 결과: \(result)")

        if result != 0 {
            print("❌ joinChannel 실패: \(result)")
            handleJoinError(result)
        } else {
            print("✅ joinChannel 호출 성공 (결과: 0)")
        }
    }

    /// 재연결 시도
    private func attemptReconnect() {
        guard !isReconnecting else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ 최대 재연결 시도 횟수 초과")
            DispatchQueue.main.async {
                self.connectionError = "연결에 실패했습니다. 다시 시도해주세요."
            }
            return
        }

        isReconnecting = true
        reconnectAttempts += 1
        let delay = TimeInterval(reconnectAttempts * 2) // 2초, 4초, 6초 지연

        print("🔄 재연결 시도 \(reconnectAttempts)/\(maxReconnectAttempts) - \(delay)초 후")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.channelName.isEmpty else { return }
            self.isReconnecting = false
            self.startCall(channel: self.channelName)
        }
    }
    
    // MARK: - 에러 처리
    private func handleJoinError(_ errorCode: Int32) {
        switch errorCode {
        case -2:
            print("❌ 잘못된 매개변수")
        case -3:
            print("❌ SDK 초기화 실패")
        case -7:
            print("❌ SDK 초기화되지 않음")
        case -17:
            print("❌ 이미 채널에 참가중")
        default:
            print("❌ 알 수 없는 에러: \(errorCode)")
        }
    }
    
    // MARK: - 통화 종료
    func endCall() {
        print("📱 통화 종료")
        agoraKit?.leaveChannel(nil)
        agoraKit?.stopPreview()

        // 토큰 캐시 정리
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
        print("🎤 음소거: \(isMuted)")
        return isMuted
    }
    
    // MARK: - 카메라 전환
    func switchCamera() {
        agoraKit?.switchCamera()
        print("📷 카메라 전환")
    }
    
    // MARK: - 카메라 토글
    func toggleCamera() -> Bool {
        isCameraOff.toggle()
        agoraKit?.muteLocalVideoStream(isCameraOff)
        print("📹 카메라: \(isCameraOff ? "OFF" : "ON")")
        return isCameraOff
    }
}

// MARK: - Agora Delegate
extension AgoraManager: AgoraRtcEngineDelegate {
    
    // 로컬 사용자가 채널에 성공적으로 참가
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        print("🎊 didJoinChannel 델리게이트 호출!")
        print("   - 채널: \(channel)")
        print("   - UID: \(uid)")
        print("   - 소요시간: \(elapsed)ms")
        
        localUserId = uid
        DispatchQueue.main.async {
            self.isInCall = true
        }
    }
    
    // 원격 사용자가 채널에 참가
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        print("👤 원격 사용자 참가: \(uid)")
        
        remoteUserId = uid
        
        // 원격 비디오 설정
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        videoCanvas.renderMode = .hidden
        
        let view = UIView()
        videoCanvas.view = view
        
        agoraKit?.setupRemoteVideo(videoCanvas)
        
        DispatchQueue.main.async {
            self.remoteVideoView = view
            self.remoteUserJoined = true
            self.remoteVideoEnabled = true  // 사용자 참가 시 비디오 활성화
        }
    }
    
    // 원격 사용자가 채널을 떠남
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        // 강제 종료나 네트워크 문제로 인한 종료인지 확인
        if reason == .dropped {
            // MatchingManager에 통화 종료 신호 전송
            MatchingManager.shared.signalCallEnd()
        }
        
        DispatchQueue.main.async {
            self.remoteUserJoined = false
            self.remoteVideoEnabled = false // 초기화
            self.remoteVideoView = nil
            self.remoteUserId = 0
        }
    }
    
    // 연결 상태 변경
    func rtcEngine(_ engine: AgoraRtcEngineKit, connectionChangedTo state: AgoraConnectionState, reason: AgoraConnectionChangedReason) {
        print("🔌 연결 상태 변경: \(state.rawValue), 이유: \(reason.rawValue)")

        switch state {
        case .disconnected:
            print("   ➜ 연결 끊김")
            // 의도적 종료가 아닌 경우 재연결 시도
            if reason != .leaveChannel && !channelName.isEmpty {
                attemptReconnect()
            }

        case .connecting:
            print("   ➜ 연결 중...")

        case .connected:
            print("   ➜ 연결됨")
            reconnectAttempts = 0
            isReconnecting = false
            DispatchQueue.main.async {
                self.connectionError = nil
            }

        case .reconnecting:
            print("   ➜ 재연결 중...")

        case .failed:
            print("   ➜ 연결 실패")
            print("      ❌ 원인 코드: \(reason.rawValue)")

            // 토큰 만료인 경우 토큰 갱신 후 재연결
            if reason == .tokenExpired {
                print("🔑 토큰 만료 - 갱신 시도")
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

    // 토큰 만료 경고
    func rtcEngine(_ engine: AgoraRtcEngineKit, tokenPrivilegeWillExpire token: String) {
        print("⚠️ 토큰 곧 만료 - 갱신 요청")
        tokenService.refreshToken(channelName: channelName, uid: localUserId) { [weak self] result in
            if case .success(let response) = result {
                self?.currentToken = response.token
                self?.agoraKit?.renewToken(response.token)
                print("✅ 토큰 갱신 완료")
            }
        }
    }

    // 에러 발생
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print("❌ Agora 에러: \(errorCode.rawValue)")
    }
    
    // 경고 발생
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        print("⚠️ Agora 경고: \(warningCode.rawValue)")
    }
    
    // 원격 사용자의 비디오 상태 변경
    func rtcEngine(_ engine: AgoraRtcEngineKit, remoteVideoStateChangedOfUid uid: UInt, state: AgoraVideoRemoteState, reason: AgoraVideoRemoteReason, elapsed: Int) {
        print("📹 원격 비디오 상태 변경: UID \(uid), 상태: \(state.rawValue), 이유: \(reason.rawValue)")
        
        DispatchQueue.main.async {
            switch state {
            case .stopped, .frozen:
                self.remoteVideoEnabled = false
                print("   ➜ 원격 비디오 비활성화")
            case .starting, .decoding:
                self.remoteVideoEnabled = true
                print("   ➜ 원격 비디오 활성화")
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Performance Optimizations
    private func setupPerformanceOptimizations() {
        guard let agoraKit = agoraKit else { return }
        
        // 비디오 품질 적응형 설정
        setupAdaptiveVideoConfig()
        
        // 오디오 처리 최적화
        agoraKit.setAudioProfile(.speechStandard, scenario: .default)
        
        // 에코 캔슬레이션 및 노이즈 억제
        agoraKit.enableAudio()
        agoraKit.enableVideo()
        
        // 하드웨어 가속 활성화
        agoraKit.setEnableSpeakerphone(true)
        
        // 네트워크 적응 활성화
        agoraKit.enableDualStreamMode(true)
        
        print("🚀 Agora 성능 최적화 설정 완료")
    }
    
    private func setupAdaptiveVideoConfig() {
        guard let agoraKit = agoraKit else { return }
        
        let videoConfig = AgoraVideoEncoderConfiguration()
        let networkQuality = PerformanceMonitor.shared.getNetworkQuality()
        
        // 네트워크 상태에 따른 동적 품질 조정
        switch networkQuality {
        case .excellent:
            videoConfig.dimensions = AgoraVideoDimension960x720
            videoConfig.frameRate = .fps30
            videoConfig.bitrate = 1130
            print("📶 네트워크 품질: 최고 - 고품질 비디오 설정")
            
        case .good:
            videoConfig.dimensions = AgoraVideoDimension640x480
            videoConfig.frameRate = .fps24
            videoConfig.bitrate = 800
            print("📶 네트워크 품질: 양호 - 중품질 비디오 설정")
            
        case .poor:
            videoConfig.dimensions = AgoraVideoDimension320x240
            videoConfig.frameRate = .fps15
            videoConfig.bitrate = 200
            print("📶 네트워크 품질: 나쁨 - 저품질 비디오 설정")
            
        default:
            videoConfig.dimensions = AgoraVideoDimension640x480
            videoConfig.frameRate = .fps24
            videoConfig.bitrate = AgoraVideoBitrateStandard
            print("📶 네트워크 품질: 알 수 없음 - 기본 품질 설정")
        }
        
        // 성능 최적화 설정 (API 버전 호환성 확인)
        videoConfig.mirrorMode = .disabled  // 불필요한 미러링 비활성화
        
        agoraKit.setVideoEncoderConfiguration(videoConfig)
    }
    
    // 네트워크 상태 변화에 따른 동적 품질 조정
    func adaptVideoQualityToNetwork() {
        setupAdaptiveVideoConfig()
    }
    
    // 성능 메트릭 수집
    func collectPerformanceMetrics() {
        guard let agoraKit = agoraKit else { return }
        
        // 연결 상태 정보 수집
        print("📊 Agora Performance Metrics:")
        print("   - Remote User Joined: \(remoteUserJoined)")
        print("   - Remote Video Enabled: \(remoteVideoEnabled)")
        print("   - Is In Call: \(isInCall)")
    }
}
