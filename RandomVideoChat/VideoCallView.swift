import SwiftUI
import UIKit
import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase

// MARK: - VideoCallView
@available(iOS 15.0, *)
struct VideoCallView: View {
    // MARK: - Properties
    @StateObject private var viewModel = VideoCallViewModel()
    @StateObject private var agoraManager = AgoraManager.shared

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationMode) var presentationMode

    // MARK: - Body
    var body: some View {
        ZStack {
            // 원격 비디오 전체 화면
            remoteVideoLayer

            // 전체 화면 상하단 그라데이션
            gradientOverlay

            // 상단 좌측 신고/차단 버튼
            reportBlockButtons

            // 우측 하단 PIP와 컨트롤들
            pipAndControls

            // 좌측 하단 타이머
            timerDisplay

            // 하단 가운데 +60초 버튼
            addTimeButton

            // 우측 하단 통화종료 버튼
            endCallButton

            // 연결 에러 알림 배너
            if let error = agoraManager.connectionError {
                errorBanner(error: error)
            }

            // 네트워크 품질 표시 (DEBUG 모드)
            #if DEBUG
            networkQualityOverlay
            #endif
        }
        .onAppear {
            viewModel.setupVideoCall()
        }
        .onChange(of: agoraManager.remoteUserJoined) { joined in
            if joined {
                viewModel.handleRemoteUserJoined()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            viewModel.handleAppTermination()
        }
        .onChange(of: scenePhase) { newPhase in
            viewModel.handleScenePhaseChange(newPhase) {
                presentationMode.wrappedValue.dismiss()
            }
        }
        .onDisappear {
            viewModel.handleDisappear()
        }
        .alert("사용자 신고", isPresented: $viewModel.showReportAlert) {
            Button("스팸/광고") { reportUser(reason: "스팸/광고") }
            Button("부적절한 콘텐츠") { reportUser(reason: "부적절한 콘텐츠") }
            Button("욕설/괴롭힘") { reportUser(reason: "욕설/괴롭힘") }
            Button("기타") { reportUser(reason: "기타") }
            Button("취소", role: .cancel) { }
        } message: {
            Text("이 사용자를 신고하는 이유를 선택해주세요.")
        }
        .alert("사용자 차단", isPresented: $viewModel.showBlockAlert) {
            Button("차단", role: .destructive) { blockUser() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("이 사용자를 차단하시겠습니까? 차단된 사용자와는 다시 매칭되지 않습니다.")
        }
    }

    // MARK: - View Components

    private var remoteVideoLayer: some View {
        AgoraVideoView(isLocal: false)
            .ignoresSafeArea()
    }

    private var gradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.6), location: 0.0),
                .init(color: Color.black.opacity(0.05), location: 0.25),
                .init(color: Color.clear, location: 0.5),
                .init(color: Color.black.opacity(0.05), location: 0.75),
                .init(color: Color.black.opacity(0.7), location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var reportBlockButtons: some View {
        VStack {
            HStack {
                VStack(spacing: 12) {
                    // 신고 버튼
                    Button(action: { viewModel.showReportAlert = true }) {
                        Circle()
                            .fill(Color.orange.opacity(0.4))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            )
                    }

                    // 차단 버튼
                    Button(action: { viewModel.showBlockAlert = true }) {
                        Circle()
                            .fill(Color.red.opacity(0.4))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "nosign")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            )
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 45)

                Spacer()
            }

            Spacer()
        }
    }

    private var pipAndControls: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                VStack(spacing: 12) {
                    // PIP 비디오
                    pipVideoView

                    // 카메라 아이콘과 마이크 아이콘
                    mediaControlButtons

                    // 하트 개수 표시
                    heartCountDisplay
                }
                .padding(.trailing, 20)
                .padding(.bottom, 180)
            }
        }
    }

    private var pipVideoView: some View {
        ZStack {
            if viewModel.isCameraOn {
                AgoraVideoView(isLocal: true)
                    .frame(width: 100, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: 100, height: 140)
                    .overlay(
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private var mediaControlButtons: some View {
        HStack(spacing: 12) {
            // 카메라 아이콘
            Button(action: {
                viewModel.toggleCamera()
            }) {
                Image(systemName: viewModel.isCameraOn ? "camera.fill" : "camera")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }

            // 마이크 아이콘
            Button(action: {
                viewModel.toggleMute()
            }) {
                ZStack {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)

                    // 마이크 꺼진 상태에서 사선 표시
                    if viewModel.isMuted {
                        Rectangle()
                            .frame(width: 35, height: 2)
                            .foregroundColor(.red)
                            .rotationEffect(.degrees(45))
                            .offset(x: 0, y: -2)
                    }
                }
            }
        }
    }

    private var heartCountDisplay: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 22))
                .foregroundColor(.red)
            Text("X  \(viewModel.heartCount)")
                .font(.custom("Carter One", size: 22))
                .foregroundColor(.white)
                .scaleEffect(viewModel.heartCountAnimation ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.4), value: viewModel.heartCountAnimation)
        }
    }

    private var timerDisplay: some View {
        VStack {
            Spacer()

            HStack {
                Text("\(viewModel.timeRemaining)")
                    .font(.custom("Carter One", size: 36))
                    .foregroundColor(viewModel.timeRemaining <= 5 ? .red : .white)
                    .monospacedDigit()
                    .padding(.leading, 20)
                    .padding(.bottom, 180)

                Spacer()
            }
        }
    }

    private var addTimeButton: some View {
        VStack {
            Spacer()

            Button(action: {
                viewModel.addTime()
            }) {
                VStack(spacing: 4) {
                    Image("plus.square")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.white)
                    Text("60s")
                        .font(.custom("Carter One", size: 16))
                        .foregroundColor(.white)
                }
            }
            .disabled(viewModel.heartCount <= 0)
            .opacity(viewModel.heartCount <= 0 ? 0.5 : 1.0)
            .padding(.bottom, 50)
        }
    }

    private var endCallButton: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button(action: endVideoCall) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        )
                }
                .padding(.trailing, 40)
            }
            .padding(.bottom, 65)
        }
    }

    private func errorBanner(error: String) -> some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    agoraManager.connectionError = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.8))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.top, 100)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: agoraManager.connectionError)
    }

    #if DEBUG
    private var networkQualityOverlay: some View {
        VStack {
            HStack {
                Spacer()
                NetworkQualityIndicator()
                    .padding(.trailing, 20)
                    .padding(.top, 50)
            }
            Spacer()
        }
    }
    #endif

    // MARK: - Actions

    private func endVideoCall() {
        viewModel.endVideoCall {
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func reportUser(reason: String) {
        viewModel.reportUser(reason: reason) {
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func blockUser() {
        viewModel.blockUser {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Network Quality Indicator
struct NetworkQualityIndicator: View {
    @StateObject private var performanceMonitor = PerformanceMonitor.shared

    var body: some View {
        HStack(spacing: 4) {
            // 신호 바
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: CGFloat(8 + index * 4))
            }

            // 연결 타입
            Text(performanceMonitor.connectionType.description)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
        .cornerRadius(8)
    }

    private func barColor(for index: Int) -> Color {
        let quality = performanceMonitor.currentNetworkQuality

        switch quality {
        case .excellent:
            return .green
        case .good:
            return index < 2 ? .yellow : .gray.opacity(0.3)
        case .poor:
            return index < 1 ? .red : .gray.opacity(0.3)
        case .unknown:
            return .gray.opacity(0.3)
        }
    }
}
