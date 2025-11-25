import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@available(iOS 15.0, *)
struct AuthenticationView: View {
    @Binding var isAuthenticated: Bool
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Enhanced dynamic gradient background
            ZStack {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.sRGB, red: 0.02, green: 0.02, blue: 0.08), location: 0.0),
                        .init(color: Color(.sRGB, red: 0.08, green: 0.03, blue: 0.15), location: 0.3),
                        .init(color: Color(.sRGB, red: 0.15, green: 0.05, blue: 0.25), location: 0.6),
                        .init(color: Color(.sRGB, red: 0.05, green: 0.02, blue: 0.12), location: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Animated mesh gradient overlay
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(.sRGB, red: 0.3, green: 0.1, blue: 0.4).opacity(0.3),
                        Color.clear
                    ]),
                    center: .topTrailing,
                    startRadius: 50,
                    endRadius: 400
                )
            }
            .ignoresSafeArea()
            
            // Enhanced floating particles with varied animations
            GeometryReader { geometry in
                ForEach(0..<20, id: \.self) { index in
                    let size = CGFloat.random(in: 20...100)
                    let opacity = Double.random(in: 0.03...0.08)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.sRGB, red: 0.7, green: 0.4, blue: 0.9).opacity(opacity),
                                    Color.white.opacity(opacity * 0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                        .position(
                            x: CGFloat.random(in: -size...geometry.size.width + size),
                            y: CGFloat.random(in: -size...geometry.size.height + size)
                        )
                        .blur(radius: CGFloat.random(in: 15...25))
                        .animation(
                            .easeInOut(duration: Double.random(in: 4...8))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: isLoading
                        )
                }
            }
            
            VStack(spacing: 50) {
                // Modern app branding with enhanced effects
                VStack(spacing: 25) {
                    ZStack {
                        // Multiple layered glow effects
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(.sRGB, red: 0.8, green: 0.3, blue: 1.0),
                                            Color(.sRGB, red: 0.5, green: 0.6, blue: 1.0)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120 + CGFloat(index * 20), height: 120 + CGFloat(index * 20))
                                .blur(radius: 25 + CGFloat(index * 10))
                                .opacity(0.3 - Double(index) * 0.1)
                        }
                        
                        // Modern app logo with inline implementation
                        ZStack {
                            // Gradient background with multiple layers
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(.sRGB, red: 0.8, green: 0.3, blue: 1.0).opacity(0.6 - Double(index) * 0.2),
                                                Color(.sRGB, red: 0.5, green: 0.6, blue: 1.0).opacity(0.4 - Double(index) * 0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 110 + CGFloat(index * 10), height: 110 + CGFloat(index * 10))
                                    .blur(radius: CGFloat(index * 5))
                            }
                            
                            // Main logo container
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 110, height: 110)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.6),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                            
                            // App name with glow
                            ZStack {
                                Text("5SEC")
                                    .font(.system(size: 27, weight: .black, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .blur(radius: 8)
                                
                                Text("5SEC")
                                    .font(.system(size: 27, weight: .black, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color.white,
                                                Color(.sRGB, red: 0.9, green: 0.9, blue: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                        .shadow(color: Color(.sRGB, red: 0.6, green: 0.3, blue: 0.9).opacity(0.4), radius: 25, x: 0, y: 12)
                    }
                    
                    VStack(spacing: 8) {
                        Text("5SEC")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.white,
                                        Color(.sRGB, red: 0.9, green: 0.9, blue: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color(.sRGB, red: 0.7, green: 0.4, blue: 0.9).opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Text("Random Video Chat")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.9),
                                        Color.white.opacity(0.6)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("익명으로 안전하게 시작하기")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 100)
                
                Spacer()
                
                // 익명 로그인 버튼
                Button(action: {
                    signInAnonymously()
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .blur(radius: 6)
                            
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                        
                        Text("시작하기")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 32)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0).opacity(0.6), location: 0.0),
                                        .init(color: Color(.sRGB, red: 0.3, green: 0.5, blue: 1.0).opacity(0.4), location: 0.5),
                                        .init(color: Color(.sRGB, red: 0.4, green: 0.6, blue: 1.0).opacity(0.7), location: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color(.sRGB, red: 0.3, green: 0.5, blue: 1.0).opacity(0.4), radius: 20, x: 0, y: 10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 25)
            }
            
            // 로딩 인디케이터
            if isLoading {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)
            }
        }
    }
    
    // 익명 로그인 함수
    func signInAnonymously() {
        isLoading = true

        Auth.auth().signInAnonymously { authResult, error in
            if let error = error {
                AppLogger.auth.error("익명 로그인 실패", error: error)
                self.isLoading = false
                return
            }

            AppLogger.auth.notice("익명 로그인 성공 - uid: \(authResult?.user.uid ?? "")")

            if let user = authResult?.user {
                UserManager.shared.loadCurrentUser(uid: user.uid)
            }

            self.isAuthenticated = true
            self.isLoading = false
        }
    }
}

#Preview {
    AuthenticationView(isAuthenticated: .constant(false))
}