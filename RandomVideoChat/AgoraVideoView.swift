import SwiftUI
import AgoraRtcKit

struct AgoraVideoView: UIViewRepresentable {
    let isLocal: Bool

    // Coordinator를 통해 상태 변화 추적
    func makeCoordinator() -> Coordinator {
        Coordinator(isLocal: isLocal)
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .black
        containerView.tag = isLocal ? 100 : 200

        // 초기 설정
        context.coordinator.setupInitialView(containerView)

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateVideoView(uiView)
    }

    // MARK: - Coordinator
    class Coordinator {
        let isLocal: Bool
        private weak var currentVideoView: UIView?
        private weak var profileView: UIView?
        private var lastVideoViewIdentifier: ObjectIdentifier?
        private var lastShowProfile: Bool?

        init(isLocal: Bool) {
            self.isLocal = isLocal
        }

        func setupInitialView(_ containerView: UIView) {
            updateVideoView(containerView)
        }

        func updateVideoView(_ containerView: UIView) {
            let agoraManager = AgoraManager.shared

            // 현재 상태 확인
            let videoView: UIView? = isLocal ? agoraManager.localVideoView : agoraManager.remoteVideoView
            let shouldShowProfile = (isLocal && agoraManager.isCameraOff) ||
                                   (!isLocal && agoraManager.remoteUserJoined && !agoraManager.remoteVideoEnabled)

            // 상태가 동일하면 업데이트 스킵
            let currentViewId = videoView.map { ObjectIdentifier($0) }
            if currentViewId == lastVideoViewIdentifier && shouldShowProfile == lastShowProfile {
                return
            }

            // 상태 저장
            lastVideoViewIdentifier = currentViewId
            lastShowProfile = shouldShowProfile

            // 기존 뷰가 동일하면 재사용
            if let videoView = videoView, !shouldShowProfile {
                if currentVideoView === videoView {
                    return // 동일한 비디오 뷰면 스킵
                }

                // 기존 서브뷰 제거
                containerView.subviews.forEach { $0.removeFromSuperview() }
                profileView = nil

                // 비디오 뷰 추가
                containerView.addSubview(videoView)
                videoView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    videoView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    videoView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    videoView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    videoView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])

                currentVideoView = videoView

            } else {
                // 프로필 뷰가 이미 있으면 재사용
                if profileView != nil && shouldShowProfile {
                    return
                }

                // 기존 서브뷰 제거
                containerView.subviews.forEach { $0.removeFromSuperview() }
                currentVideoView = nil

                // 프로필 뷰 생성
                let newProfileView = createProfileView(
                    showWaitingLabel: !isLocal && videoView == nil
                )

                containerView.addSubview(newProfileView)
                newProfileView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    newProfileView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    newProfileView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    newProfileView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    newProfileView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])

                profileView = newProfileView
            }
        }

        private func createProfileView(showWaitingLabel: Bool) -> UIView {
            let profileContainer = UIView()
            profileContainer.backgroundColor = .black

            // 프로필 아이콘
            let profileIcon = UIImageView()
            profileIcon.image = UIImage(systemName: "person.crop.circle.fill")
            profileIcon.tintColor = UIColor.white.withAlphaComponent(0.5)
            profileIcon.contentMode = .scaleAspectFit
            profileIcon.translatesAutoresizingMaskIntoConstraints = false

            profileContainer.addSubview(profileIcon)

            NSLayoutConstraint.activate([
                profileIcon.centerXAnchor.constraint(equalTo: profileContainer.centerXAnchor),
                profileIcon.centerYAnchor.constraint(equalTo: profileContainer.centerYAnchor),
                profileIcon.widthAnchor.constraint(equalTo: profileContainer.widthAnchor, multiplier: 0.3),
                profileIcon.heightAnchor.constraint(equalTo: profileIcon.widthAnchor)
            ])

            // 대기 레이블
            if showWaitingLabel {
                let label = UILabel()
                label.text = "상대방 대기중..."
                label.textColor = .white
                label.textAlignment = .center
                label.font = UIFont.systemFont(ofSize: 14)
                label.translatesAutoresizingMaskIntoConstraints = false

                profileContainer.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: profileContainer.centerXAnchor),
                    label.topAnchor.constraint(equalTo: profileIcon.bottomAnchor, constant: 16)
                ])
            }

            return profileContainer
        }
    }
}
