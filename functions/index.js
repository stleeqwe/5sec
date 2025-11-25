/**
 * 5sec Video Chat - Agora Token Server
 * Firebase Cloud Functions
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {RtcTokenBuilder, RtcRole} = require("agora-access-token");

admin.initializeApp();

// Agora 자격 증명 (Firebase Functions 환경변수에서 가져옴)
// 배포 전 설정 필요: firebase functions:config:set agora.app_id="YOUR_APP_ID" agora.app_certificate="YOUR_CERTIFICATE"
const getAgoraCredentials = () => {
  const appId = process.env.AGORA_APP_ID || functions.config().agora?.app_id;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE || functions.config().agora?.app_certificate;

  if (!appId || !appCertificate) {
    throw new Error("Agora credentials not configured. Please set AGORA_APP_ID and AGORA_APP_CERTIFICATE.");
  }

  return {appId, appCertificate};
};

/**
 * Agora RTC 토큰 생성 함수
 *
 * Request body:
 * - channelName: string (필수) - 채널 이름
 * - uid: number (선택) - 사용자 ID, 없으면 0
 * - role: string (선택) - "publisher" 또는 "subscriber", 기본값 "publisher"
 * - expireTime: number (선택) - 토큰 만료 시간(초), 기본값 3600 (1시간)
 *
 * Response:
 * - token: string - 생성된 RTC 토큰
 * - expireTimestamp: number - 토큰 만료 Unix 타임스탬프
 */
exports.generateAgoraToken = functions.https.onCall(async (data, context) => {
  // 인증 확인
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "인증이 필요합니다. 로그인 후 다시 시도해주세요.",
    );
  }

  const {channelName, uid = 0, role = "publisher", expireTime = 3600} = data;

  // 채널 이름 유효성 검사
  if (!channelName || typeof channelName !== "string") {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "유효한 채널 이름이 필요합니다.",
    );
  }

  if (channelName.length > 64) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "채널 이름은 64자를 초과할 수 없습니다.",
    );
  }

  // 만료 시간 검증 (최소 60초, 최대 24시간)
  const validExpireTime = Math.max(60, Math.min(expireTime, 86400));

  try {
    const {appId, appCertificate} = getAgoraCredentials();

    // RTC 역할 설정
    const rtcRole = role === "subscriber" ? RtcRole.SUBSCRIBER : RtcRole.PUBLISHER;

    // 만료 타임스탬프 계산
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + validExpireTime;

    // 토큰 생성
    const token = RtcTokenBuilder.buildTokenWithUid(
        appId,
        appCertificate,
        channelName,
        uid,
        rtcRole,
        privilegeExpiredTs,
    );

    // 로그 기록 (보안상 토큰 값은 로깅하지 않음)
    console.log(`Token generated for user: ${context.auth.uid}, channel: ${channelName}`);

    // 사용자 활동 기록 (선택적)
    await admin.firestore().collection("token_logs").add({
      userId: context.auth.uid,
      channelName: channelName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(privilegeExpiredTs * 1000),
    });

    return {
      token: token,
      expireTimestamp: privilegeExpiredTs,
      channelName: channelName,
      uid: uid,
    };
  } catch (error) {
    console.error("Token generation error:", error);
    throw new functions.https.HttpsError(
        "internal",
        "토큰 생성에 실패했습니다. 잠시 후 다시 시도해주세요.",
    );
  }
});

/**
 * 토큰 갱신 함수
 * 기존 통화 중 토큰이 만료되기 전에 갱신
 */
exports.refreshAgoraToken = functions.https.onCall(async (data, context) => {
  // 인증 확인
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "인증이 필요합니다.",
    );
  }

  const {channelName, uid = 0} = data;

  if (!channelName) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "채널 이름이 필요합니다.",
    );
  }

  try {
    const {appId, appCertificate} = getAgoraCredentials();

    // 갱신 시 30분 추가
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + 1800; // 30분

    const token = RtcTokenBuilder.buildTokenWithUid(
        appId,
        appCertificate,
        channelName,
        uid,
        RtcRole.PUBLISHER,
        privilegeExpiredTs,
    );

    console.log(`Token refreshed for user: ${context.auth.uid}, channel: ${channelName}`);

    return {
      token: token,
      expireTimestamp: privilegeExpiredTs,
    };
  } catch (error) {
    console.error("Token refresh error:", error);
    throw new functions.https.HttpsError(
        "internal",
        "토큰 갱신에 실패했습니다.",
    );
  }
});

/**
 * 매칭 완료 시 자동으로 토큰 생성 (Realtime Database 트리거)
 * matches/{matchId}가 생성되면 양쪽 사용자에게 토큰 제공
 */
exports.onMatchCreated = functions.database.ref("/matches/{matchId}")
    .onCreate(async (snapshot, context) => {
      const matchData = snapshot.val();
      const matchId = context.params.matchId;

      if (!matchData || matchData.status !== "active") {
        return null;
      }

      const {user1, user2, channelName} = matchData;

      if (!user1 || !user2 || !channelName) {
        console.log("Invalid match data:", matchId);
        return null;
      }

      try {
        const {appId, appCertificate} = getAgoraCredentials();

        const currentTimestamp = Math.floor(Date.now() / 1000);
        const privilegeExpiredTs = currentTimestamp + 3600; // 1시간

        // 두 사용자 모두에게 동일한 채널용 토큰 생성
        const token = RtcTokenBuilder.buildTokenWithUid(
            appId,
            appCertificate,
            channelName,
            0, // uid 0 = 자동 할당
            RtcRole.PUBLISHER,
            privilegeExpiredTs,
        );

        // 매칭 데이터에 토큰 추가
        await snapshot.ref.update({
          agoraToken: token,
          tokenExpireAt: privilegeExpiredTs,
        });

        console.log(`Token auto-generated for match: ${matchId}`);

        return {success: true};
      } catch (error) {
        console.error("Auto token generation error:", error);
        return {success: false, error: error.message};
      }
    });

/**
 * 헬스 체크 엔드포인트
 */
exports.healthCheck = functions.https.onRequest((req, res) => {
  res.status(200).json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    service: "5sec-agora-token-server",
  });
});
