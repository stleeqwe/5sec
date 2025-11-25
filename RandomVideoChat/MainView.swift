import SwiftUI
import FirebaseAuth
import AVFoundation

@available(iOS 15.0, *)
struct MainView: View {
    @State private var isCameraOn = true
    @State private var heartCount = 3  // 기본 하트 개수
    @State private var showMatchingView = false
    @StateObject private var userManager = UserManager.shared
    @State private var permissionsGranted = false
    @State private var swipeOffset: CGFloat = 0
    @State private var showSwipeHint = true
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    @State private var showSettings = false
    @State private var showAppleSignInAlert = false
    
    var body: some View {
        ZStack {
            if isCameraOn {
                // 실제 카메라 프리뷰
                CameraPreview(isOn: $isCameraOn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 카메라 off 상태 기본 프로필 화면
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 200))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            
            // 전체 화면 카메라 오버레이 (상단과 하단에 그라데이션 적용)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.4), location: 0.0),  // 상단 어두움
                    .init(color: Color.black.opacity(0.05), location: 0.25), // 중간 위쪽 밝음
                    .init(color: Color.black.opacity(0.02), location: 0.5),  // 중앙 완전 밝음
                    .init(color: Color.black.opacity(0.05), location: 0.75), // 중간 아래쪽 밝음
                    .init(color: Color.black.opacity(0.7), location: 1.0)    // 하단 어두움
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack {
                // 상단 버튼들
                HStack {
                    Spacer()
                    
                    // Apple Sign In 버튼 (미구현)
                    Button(action: { showAppleSignInAlert = true }) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 15)
                    
                    // 설정 버튼
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                }
                
                Spacer()
                
                HStack {
                    // 성별 선택 UI (좌측)
                    VStack(spacing: 20) {
                        GenderSelectionView(
                            title: "내 성별",
                            isRequired: true,
                            selectedGender: userManager.currentUser?.gender,
                            onGenderSelected: { gender in
                                userManager.updateGender(gender)
                            }
                        )
                        
                        GenderSelectionView(
                            title: "선호 성별",
                            isRequired: false,
                            selectedGender: userManager.currentUser?.preferredGender,
                            onGenderSelected: { gender in
                                // 선호 성별은 토글 가능 - 같은 성별 재선택 시 해제
                                if userManager.currentUser?.preferredGender == gender {
                                    userManager.updatePreferredGender(nil)
                                } else {
                                    userManager.updatePreferredGender(gender)
                                }
                            }
                        )
                    }
                    .padding(.leading, 20)
                    
                    Spacer()
                    
                    // 카메라 아이콘과 하트 카운터 (우측 상단)
                    VStack(spacing: 12) {
                        Button(action: {
                            isCameraOn.toggle()
                            // 카메라 상태를 UserDefaults에 저장
                            UserDefaults.standard.set(isCameraOn, forKey: "isCameraOn")
                        }) {
                            Image(systemName: isCameraOn ? "camera.fill" : "camera")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.red)
                            Text("X  \(heartCount)")
                                .font(.custom("Carter One", size: 22))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 30)
                
                // 인터랙티브 스와이프 인디케이터 (중앙 하단)
                VStack(spacing: 16) {
                    // 순차적으로 나타나는 상향 화살표
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            Image(systemName: "chevron.up")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .opacity(showSwipeHint ? 1.0 : 0.3)
                                .scaleEffect(showSwipeHint ? 1.0 : 0.7)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                    value: showSwipeHint
                                )
                        }
                    }
                    .offset(y: swipeOffset)
                    
                    Text("SWIPE UP & START")
                        .font(.custom("Carter One", size: 20))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 70)
                .onAppear {
                    // Enhanced floating animation
                    withAnimation(
                        .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                    ) {
                        swipeOffset = -15
                    }
                    
                    // Pulsing hint animation
                    withAnimation(
                        .easeInOut(duration: 3.0)
                            .repeatForever(autoreverses: true)
                    ) {
                        showSwipeHint.toggle()
                    }
                }
            }
            
            // 🆕 디버그 정보 (개발용)
            #if DEBUG
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("세션 제외: \(UserManager.shared.getRecentMatchesCount())명")
                            .font(.caption2)
                        
                        let blockedCount = UserManager.shared.currentUser?.blockedUsers.count ?? 0
                        Text("영구 차단: \(blockedCount)명")
                            .font(.caption2)
                    }
                    .padding(5)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(5)
                    
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.horizontal)
                
                Spacer()
            }
            #endif
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    // 위로 스와이프 감지
                    if value.translation.height < -50 {
                        // 성별 선택 확인
                        if userManager.currentUser?.gender != nil {
                            showMatchingView = true
                        } else {
                            permissionMessage = "매칭을 시작하려면 먼저 성별을 선택해주세요."
                            showPermissionAlert = true
                        }
                    }
                }
        )
        .alert(isPresented: $showPermissionAlert) {
            if permissionMessage.contains("성별") {
                // 성별 선택 알림
                Alert(title: Text("성별 선택 필요"),
                      message: Text(permissionMessage),
                      dismissButton: .default(Text("확인")))
            } else {
                // 권한 관련 알림
                Alert(title: Text("권한 필요"),
                      message: Text(permissionMessage),
                      primaryButton: .default(Text("설정 열기"), action: {
                          openSettings()
                      }),
                      secondaryButton: .cancel(Text("닫기")))
            }
        }
        .alert("Apple Sign In", isPresented: $showAppleSignInAlert) {
            Button("확인") { }
        } message: {
            Text("Apple Sign In 기능은 현재 개발 중입니다. 곧 업데이트될 예정입니다.")
        }
        .onAppear {
            // 저장된 카메라 상태 복원
            isCameraOn = UserDefaults.standard.bool(forKey: "isCameraOn")
            // 기본값이 false이므로 한번도 설정하지 않았다면 true로 설정
            if UserDefaults.standard.object(forKey: "isCameraOn") == nil {
                isCameraOn = true
                UserDefaults.standard.set(true, forKey: "isCameraOn")
            }
            
            // 권한 요청
            checkPermissions()
            requestPermissions()
            
            // 현재 사용자 데이터 로드
            if let uid = Auth.auth().currentUser?.uid {
                userManager.loadCurrentUser(uid: uid)
            }
        }
        .onReceive(userManager.$currentUser) { user in
            // Firestore에서 가져온 값 우선 사용
            if let user = user {
                heartCount = user.heartCount
                UserDefaults.standard.set(heartCount, forKey: "heartCount")
            } else {
                // Firestore에 데이터가 없으면 UserDefaults 확인
                let saved = UserDefaults.standard.integer(forKey: "heartCount")
                heartCount = saved > 0 ? saved : 3
            }
        }
        // 🆕 중요: fullScreenCover 추가!!!
        .fullScreenCover(isPresented: $showMatchingView) {
            MatchingView(isPresented: $showMatchingView)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    func checkPermissions() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus    = AVCaptureDevice.authorizationStatus(for: .audio)

        // 카메라 권한 처리
        switch cameraStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.checkPermissions()
                    } else {
                        self.permissionMessage = "카메라 권한이 필요합니다. 설정에서 권한을 허용해주세요."
                        self.showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            self.permissionMessage = "카메라 권한이 필요합니다. 설정에서 권한을 허용해주세요."
            self.showPermissionAlert = true
        default:
            break
        }

        // 마이크 권한 처리
        switch micStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.permissionMessage = "마이크 권한이 필요합니다. 설정에서 권한을 허용해주세요."
                        self.showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            self.permissionMessage = "마이크 권한이 필요합니다. 설정에서 권한을 허용해주세요."
            self.showPermissionAlert = true
        default:
            break
        }
    }
    
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    
    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            AppLogger.camera.debug("카메라 권한: \(granted)")
            if granted {
                checkMicrophonePermission()
            }
        }
    }

    func checkMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            AppLogger.camera.debug("마이크 권한: \(granted)")
            DispatchQueue.main.async {
                self.permissionsGranted = granted
            }
        }
    }
}

// MARK: - Gender Selection Component
struct GenderSelectionView: View {
    let title: String
    let isRequired: Bool
    let selectedGender: Gender?
    let onGenderSelected: (Gender) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.custom("GoogleSansCode", size: 14))
                    .foregroundColor(.white)
                
                if isRequired {
                    Text("*")
                        .font(.custom("GoogleSansCode", size: 14))
                        .foregroundColor(.red)
                }
            }
            
            HStack(spacing: 12) {
                ForEach(Gender.allCases, id: \.self) { gender in
                    Button(action: {
                        onGenderSelected(gender)
                    }) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(selectedGender == gender ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: gender.icon)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(selectedGender == gender ? .black : .white)
                            }
                            
                            Text(gender.displayName)
                                .font(.custom("GoogleSansCode", size: 12))
                                .foregroundColor(selectedGender == gender ? .white : .white.opacity(0.7))
                        }
                    }
                    .scaleEffect(selectedGender == gender ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: selectedGender)
                }
            }
        }
    }
}

#Preview {
    MainView()
}
