import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@available(iOS 15.0, *)
struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var showDeleteAccountAlert = false
    @State private var isDeleting = false
    @StateObject private var userManager = UserManager.shared

    // MARK: - URL Constants
    private enum URLs {
        static let terms = URL(string: "https://5sec-terms.web.app/terms")
        static let privacy = URL(string: "https://5sec-terms.web.app/privacy")
        static let support = URL(string: "mailto:support@5sec-app.com")
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    // 이용약관
                    if let termsURL = URLs.terms {
                        Link(destination: termsURL) {
                            SettingsLinkRow(
                                icon: "doc.text",
                                title: "이용약관"
                            )
                        }
                    }

                    // 개인정보처리방침
                    if let privacyURL = URLs.privacy {
                        Link(destination: privacyURL) {
                            SettingsLinkRow(
                                icon: "lock.shield",
                                title: "개인정보처리방침"
                            )
                        }
                    }

                    // 문의하기
                    if let supportURL = URLs.support {
                        Link(destination: supportURL) {
                            SettingsLinkRow(
                                icon: "envelope",
                                title: "문의하기"
                            )
                        }
                    }
                } header: {
                    Text("정보")
                }
                
                Section {
                    Button(action: { showDeleteAccountAlert = true }) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.minus")
                                .foregroundColor(.red)
                            Text("계정 삭제")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(isDeleting)
                } header: {
                    Text("계정 관리")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 사용자 데이터 로드
            if let uid = Auth.auth().currentUser?.uid {
                userManager.loadCurrentUser(uid: uid)
            }
        }
        .alert("계정 삭제", isPresented: $showDeleteAccountAlert) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("계정을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다. 모든 데이터가 영구적으로 삭제됩니다.")
        }
    }
    
    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        
        isDeleting = true
        let uid = user.uid
        
        // Firestore 사용자 데이터 삭제
        let db = Firestore.firestore()
        db.collection("users").document(uid).delete { error in
            if let error = error {
                AppLogger.user.error("Firestore 데이터 삭제 실패", error: error)
                isDeleting = false
                return
            }

            // Firebase Auth 계정 삭제
            user.delete { error in
                isDeleting = false

                if let error = error {
                    AppLogger.auth.error("계정 삭제 실패", error: error)
                } else {
                    AppLogger.auth.notice("계정 삭제 완료")
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}

// MARK: - Settings Link Row Component
@available(iOS 15.0, *)
private struct SettingsLinkRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    SettingsView()
}