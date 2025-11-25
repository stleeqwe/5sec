import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @Binding var isFrontCamera: Bool
    
    class Coordinator: NSObject {
        var parent: CameraView
        var captureSession: AVCaptureSession?
        var currentCamera: AVCaptureDevice?
        private var isSessionRunning = false

        init(_ parent: CameraView) {
            self.parent = parent
            super.init()
        }

        deinit {
            stopSession()
            print("📷 CameraView.Coordinator deinit - 세션 정리됨")
        }

        func stopSession() {
            guard isSessionRunning, let session = captureSession else { return }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.stopRunning()
                self?.isSessionRunning = false
                print("📷 카메라 세션 중지됨")
            }
        }

        func startSession() {
            guard !isSessionRunning, let session = captureSession else { return }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                self?.isSessionRunning = true
                print("📷 카메라 세션 시작됨")
            }
        }

        func setupCamera() {
            print("📷 카메라 설정 시작...")
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .high
            
            // 전면 카메라 찾기
            if let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front) {
                print("📷 전면 카메라 찾음: \(camera.localizedName)")
                currentCamera = camera
                
                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    if captureSession?.canAddInput(input) == true {
                        captureSession?.addInput(input)
                        print("📷 카메라 입력 추가 성공")
                        
                        // 세션 설정이 완료되면 메인 스레드에서 UI 업데이트
                        DispatchQueue.main.async {
                            print("📷 카메라 설정 완료 - UI 업데이트 필요")
                        }
                    } else {
                        print("❌ 카메라 입력 추가 실패")
                    }
                } catch {
                    print("❌ 카메라 설정 오류: \(error)")
                }
            } else {
                print("❌ 전면 카메라를 찾을 수 없음")
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        print("📷 makeUIView 호출됨 - 초기 frame: \(view.frame)")
        
        // 카메라 권한 확인
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("📷 현재 카메라 권한 상태: \(currentStatus.rawValue)")
        
        if currentStatus == .authorized {
            print("📷 카메라 권한 이미 승인됨 - 바로 설정")
            DispatchQueue.main.async {
                context.coordinator.setupCamera()
                
                // 카메라 설정 후 잠시 대기 후 프리뷰 레이어 추가 시도
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.setupPreviewLayer(for: view, with: context.coordinator.captureSession)
                }
            }
        } else {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("📷 카메라 권한 요청 결과: \(granted)")
                if granted {
                    DispatchQueue.main.async {
                        context.coordinator.setupCamera()
                        
                        // 카메라 설정 후 잠시 대기 후 프리뷰 레이어 추가 시도
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.setupPreviewLayer(for: view, with: context.coordinator.captureSession)
                        }
                    }
                } else {
                    print("❌ 카메라 권한이 거부됨")
                }
            }
        }
        
        return view
    }
    
    private func setupPreviewLayer(for view: UIView, with session: AVCaptureSession?) {
        guard let session = session else {
            print("📷 setupPreviewLayer: 세션이 없음")
            return
        }
        
        // 뷰 크기가 0인 경우 강제로 화면 크기로 설정
        if view.bounds.width == 0 || view.bounds.height == 0 {
            let screenBounds = UIScreen.main.bounds
            view.frame = screenBounds
            print("📷 setupPreviewLayer: 뷰 크기를 화면 크기로 강제 설정: \(screenBounds)")
        }
        
        // 기존 프리뷰 레이어 확인
        if view.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) != nil {
            print("📷 setupPreviewLayer: 이미 프리뷰 레이어 존재")
            return
        }
        
        // 새로운 프리뷰 레이어 생성
        print("📷 setupPreviewLayer: 새로운 프리뷰 레이어 생성 - frame: \(view.bounds)")
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        
        view.layer.addSublayer(previewLayer)
        print("📷 setupPreviewLayer: 프리뷰 레이어 추가됨 - sublayers count: \(view.layer.sublayers?.count ?? 0)")
        
        // 세션 시작
        context.coordinator.startSession()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // 뷰가 제거될 때 세션 정리
        coordinator.stopSession()
        print("📷 dismantleUIView - 세션 정리됨")
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        print("📷 updateUIView 호출됨 - frame: \(uiView.bounds)")
        
        // 유효한 크기가 있으면 setupPreviewLayer 호출
        if uiView.bounds.width > 0 && uiView.bounds.height > 0 {
            setupPreviewLayer(for: uiView, with: context.coordinator.captureSession)
        } else {
            print("📷 updateUIView: 뷰 크기가 유효하지 않음")
        }
    }
}

// 카메라 미리보기를 위한 SwiftUI View
struct CameraPreview: View {
    @Binding var isOn: Bool
    
    var body: some View {
        let _ = print("📷 CameraPreview - isOn: \(isOn)")
        
        Group {
            if isOn {
                #if targetEnvironment(simulator)
                // 시뮬레이터에서는 대체 화면 표시
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    
                    VStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("카메라 프리뷰")
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                        
                        Text("(시뮬레이터)")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                #else
                // 실제 기기에서는 카메라 표시
                CameraView(isFrontCamera: .constant(true))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                #endif
            } else {
                let _ = print("📷 카메라 OFF 상태 - 대체 화면 표시")
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 150, height: 150)
                            .foregroundColor(.gray)
                    )
            }
        }
    }
}
