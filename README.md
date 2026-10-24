# DAL · 달

사용자와 dot이 여러 프로젝트의 자료를 함께 검토하는 SwiftUI Mac 앱입니다. 영상의 특정 시점과 영역에 대화를 고정하고, 요청·제안·제작 결과·사용자 결정을 같은 대화에 남깁니다.

## 구성

- SwiftUI와 AVPlayer로 만든 네이티브 화면: 프로젝트 목록, 영상과 영역 표시, 선택한 대화, 같은 구간의 전후 비교.
- 별도의 비공개 Sites 서버: D1에 프로젝트·버전·대화·결정을 저장하고 R2에 실제 영상을 보관합니다.
- Site MCP 도구: dot이 저장된 요청을 읽고 실제 응답이나 결과를 남깁니다. 자동 호출·자동 응답을 약속하지 않습니다.
- ‘이 도구 개선’ 대화: 이유와 변경 범위를 담은 제안에 사용자가 결정합니다. 결정만으로 코드를 실행하거나 앱을 배포하지 않습니다.

이 저장소에는 사용자 영상, 실제 대화, 운영 저장소 주소·식별자·인증 값이 없습니다. 새 서버는 빈 저장소로 시작합니다. 공개 소스와 사용자 데이터의 접근 범위는 별개입니다.

## 개발과 설치

macOS 14 이상, Swift 6 도구와 Python 3가 필요합니다. 서버 개발에는 Node.js 22.13 이상과 npm이 필요합니다.

```sh
cd native
swift test
cd ..
DOT_BACKEND_ORIGIN=https://your-private-site.example python3 native/scripts/build-app.py
python3 native/scripts/install-app.py --launch
```

설치 대상은 `/Applications/DAL.app`입니다. 실행 중인 설치본은 교체하지 않습니다. 빌드·설치 기록과 이전 설치본은 무시되는 `outputs/` 아래에 보관하며, 사용자 설정이나 서버 기록은 지우지 않습니다. 서명은 로컬 ad-hoc 서명이며 공증된 배포본은 아닙니다.

자세한 검증·연결 경계는 [개발 안내](docs/DEVELOPMENT.md), 데이터와 권한 설계는 [설계](docs/DESIGN.md)를 확인하세요.

## 연결 상태

앱의 **작업실 로그인**은 공식 ChatGPT 로그인 페이지를 엽니다. 메인 UI는 SwiftUI이고, WebKit은 로그인에만 사용합니다. 서버가 인증된 JSON을 반환해야 연결 상태가 됩니다. Sites는 네이티브 토큰 교환을 문서화하지 않으므로 실제 사용자 로그인, 보호 영상 재생과 쓰기 왕복을 각각 검증해야 합니다. 로그인 거부를 다른 인증 값으로 우회하지 않습니다.

현재 패스키·Touch ID·Safari의 Google 로그인 상태를 DAL 연결에 사용하는 기능은 구현되지 않았습니다. Apple은 WKWebView 패스키에 서비스와 앱의 Associated Domains 관계를 요구합니다. DAL은 OpenAI 쪽 설정을 제어하지 않습니다. 시스템 인증 세션은 올바른 대안이지만, Sites가 네이티브 앱으로 인증 상태를 돌려주는 계약은 확인되지 않았습니다. 브라우저 로그인만으로 앱이 연결됐다고 표시하거나 다른 브라우저의 쿠키·키체인·토큰을 가져오지 않습니다. ([Apple 패스키](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys), [시스템 인증 세션](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), [OpenAI 패스키](https://help.openai.com/en/articles/20001039-passkeys-to-secure-your-openai-account))

카메라와 손 제스처는 현재 구현하지 않았습니다. 마우스·키보드로 작업하며, 영상 편집·멀티트랙·클립 자르기는 제공하지 않습니다.

타사 코드의 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 보존합니다. 이 저장소 자체의 별도 라이선스는 아직 지정하지 않았습니다.
