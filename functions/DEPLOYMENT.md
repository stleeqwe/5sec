# Agora Token Server 배포 가이드

## 사전 요구사항

1. **Firebase CLI 설치**
   ```bash
   npm install -g firebase-tools
   ```

2. **Firebase 로그인**
   ```bash
   firebase login
   ```

3. **Agora 계정 및 자격 증명**
   - Agora Console (https://console.agora.io) 에서:
     - App ID 확인
     - App Certificate 활성화 및 확인

---

## 배포 단계

### 1. Dependencies 설치

```bash
cd functions
npm install
```

### 2. Agora 자격 증명 설정

Firebase Functions 환경변수에 Agora 자격 증명을 설정합니다:

```bash
firebase functions:config:set agora.app_id="YOUR_AGORA_APP_ID"
firebase functions:config:set agora.app_certificate="YOUR_AGORA_APP_CERTIFICATE"
```

**설정 확인:**
```bash
firebase functions:config:get
```

### 3. 로컬 테스트 (선택사항)

```bash
# 환경변수 파일 생성
firebase functions:config:get > .runtimeconfig.json

# 에뮬레이터 실행
npm run serve
```

### 4. 프로덕션 배포

```bash
firebase deploy --only functions
```

---

## 배포 후 확인

### Health Check
```bash
curl https://<REGION>-<PROJECT_ID>.cloudfunctions.net/healthCheck
```

### 토큰 생성 테스트 (Firebase Console)
1. Firebase Console > Functions 이동
2. `generateAgoraToken` 함수 로그 확인

---

## iOS 앱 설정

### 1. Firebase SDK 설정 확인

`Podfile` 또는 SPM에 다음 패키지가 포함되어 있는지 확인:
- `FirebaseFunctions`

### 2. Info.plist 확인

```xml
<key>AGORA_APP_ID</key>
<string>YOUR_AGORA_APP_ID</string>
```

---

## 보안 주의사항

1. **App Certificate는 절대 클라이언트에 포함하지 마세요**
   - 서버 측(Cloud Functions)에서만 사용

2. **Firebase Authentication 필수**
   - 인증되지 않은 사용자는 토큰을 생성할 수 없음

3. **토큰 만료 시간**
   - 기본값: 1시간 (3600초)
   - 통화 중 자동 갱신 구현됨

---

## 문제 해결

### "Agora credentials not configured" 에러
```bash
# 환경변수 재설정
firebase functions:config:set agora.app_id="..." agora.app_certificate="..."
firebase deploy --only functions
```

### 토큰 생성 실패
1. Agora Console에서 App Certificate가 활성화되어 있는지 확인
2. App ID와 App Certificate가 올바른지 확인
3. Firebase Functions 로그 확인:
   ```bash
   firebase functions:log
   ```

### iOS에서 "unauthenticated" 에러
- Firebase Authentication으로 로그인되어 있는지 확인
- Anonymous Auth가 활성화되어 있는지 Firebase Console에서 확인
