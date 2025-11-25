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
            AppLogger.camera.debug("CameraView.Coordinator deinit - 세션 정리됨")
        }

        func stopSession() {
            guard isSessionRunning, let session = captureSession else { return }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.stopRunning()
                self?.isSessionRunning = false
                AppLogger.camera.debug("카메라 세션 중지됨")
            }
        }

        func startSession() {
            guard !isSessionRunning, let session = captureSession else { return }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                self?.isSessionRunning = true
                AppLogger.camera.debug("카메라 세션 시작됨")
            }
        }

        func setupCamera() {
            AppLogger.camera.debug("카메라 설정 시작")
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .high

            if let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front) {
                currentCamera = camera

                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    if captureSession?.canAddInput(input) == true {
                        captureSession?.addInput(input)
                        AppLogger.camera.info("카메라 입력 추가 성공")
                    } else {
                        AppLogger.camera.error("카메라 입력 추가 실패")
                    }
                } catch {
                    AppLogger.camera.error("카메라 설정 오류", error: error)
                }
            } else {
                AppLogger.camera.error("전면 카메라를 찾을 수 없음")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)

        if currentStatus == .authorized {
            DispatchQueue.main.async {
                context.coordinator.setupCamera()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.setupPreviewLayer(for: view, with: context.coordinator.captureSession, coordinator: context.coordinator)
                }
            }
        } else {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                AppLogger.camera.info("카메라 권한 요청 결과: \(granted)")
                if granted {
                    DispatchQueue.main.async {
                        context.coordinator.setupCamera()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.setupPreviewLayer(for: view, with: context.coordinator.captureSession, coordinator: context.coordinator)
                        }
                    }
                } else {
                    AppLogger.camera.warning("카메라 권한이 거부됨")
                }
            }
        }

        return view
    }

    private func setupPreviewLayer(for view: UIView, with session: AVCaptureSession?, coordinator: Coordinator) {
        guard let session = session else {
            return
        }

        // 뷰 크기가 0인 경우 강제로 화면 크기로 설정
        if view.bounds.width == 0 || view.bounds.height == 0 {
            let screenBounds = UIScreen.main.bounds
            view.frame = screenBounds
        }

        // 기존 프리뷰 레이어 확인
        if view.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) != nil {
            return
        }

        // 새로운 프리뷰 레이어 생성
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill

        view.layer.addSublayer(previewLayer)

        // 세션 시작
        coordinator.startSession()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSession()
        AppLogger.camera.debug("dismantleUIView - 세션 정리됨")
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if uiView.bounds.width > 0 && uiView.bounds.height > 0 {
            setupPreviewLayer(for: uiView, with: context.coordinator.captureSession, coordinator: context.coordinator)
        }
    }
}

// 카메라 미리보기를 위한 SwiftUI View
struct CameraPreview: View {
    @Binding var isOn: Bool

    var body: some View {
        Group {
            if isOn {
                #if targetEnvironment(simulator)
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
                CameraView(isFrontCamera: .constant(true))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                #endif
            } else {
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
