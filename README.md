# 3F

Personal macOS utility that converts a **three-finger tap or physical click** on
the built-in trackpad into a middle mouse click, and a **middle-button mouse gesture**
into Mission Control (drag up) or desktop space switching (drag left/right). A physical
middle-button click on non-interactive content starts Windows-style automatic scrolling.

## What it does

- Detects raw trackpad frames with `MultitouchSupport.framework`, opened at runtime.
- Accepts only an exact three-finger tap: all three touches must release within
  220 ms, their release may be spread across at most 80 ms, their centroid may
  move at most `0.020`, and any fourth touch cancels the gesture.
- Converts a physical three-finger trackpad click from left-click down/up events
  into middle-button down/up events, suppressing the original left click.
- Posts a Core Graphics middle-click at the current cursor location.
- Hold the physical mouse middle button and move upward at least 80 points to
  open Mission Control, or move left/right at least 60 points to switch desktops
  (like a trackpad swipe: drag left for next desktop, drag right for previous desktop).
  The pointer stays at the moved position. A click within 8 points over an accessible
  interactive control remains a normal middle click.
- Click the physical mouse middle button elsewhere to show a four-way anchor.
  Moving the pointer outside its 12-point dead zone scrolls vertically in the
  reverse direction and horizontally in the same direction, accelerating as
  the pointer moves farther away; any mouse button or Escape stops scrolling.
  Accessible non-interactive content, including plain text, can start automatic
  scrolling.
  Links, tabs, buttons, and other pressable controls keep their original middle
  click. If an app does not expose the target through the macOS Accessibility
  API, 3F preserves the original middle click.
- Provides a small menu-bar menu for Enabled, the mouse gesture, automatic
  scrolling, Launch at Login, and Quit.

`MultitouchSupport` is a private macOS framework. This is deliberately a
personal-use utility and may need adjustment after macOS updates.

## Privacy and security

- The app reads raw built-in-trackpad contact frames only while **Enabled**.
  It installs its global mouse event filter only while an input feature is
  running, and removes it when disabled or when the app quits. Mouse features
  can remain available if no trackpad is present. The filter passes keyboard
  input through unchanged and checks only for Escape while automatic scrolling
  is active.
- Contact positions, mouse events, and diagnostics are not written to files or
  sent over the network. The only persisted values are preferences for Enabled,
  the mouse gesture, automatic scrolling, and the Dock icon, plus aggregate
  diagnostics shown in the status window.
- Accessibility permission is required because the app suppresses qualifying
  mouse events and posts replacement input. Review that permission before
  granting it, and disable the app when it is not needed.
- `MultitouchSupport` is a private, unsupported framework. Its ABI may change
  in a macOS update; this app is not suitable for the Mac App Store and Apple
  does not guarantee its continued operation.

3F is independent software and is not affiliated with,
endorsed by, or supported by Apple.

## Build

Requirements: Xcode Command Line Tools, Rust, and an Apple-silicon Mac running
macOS 13 or later.

```sh
brew install rust
make app
open dist/3F.app
```

The built app is at `dist/3F.app`. On first launch, macOS
will ask for Accessibility permission; allow it under **System Settings →
Privacy & Security → Accessibility** so the app can post the middle-click.

To create a compressed disk image for storage or transfer:

```sh
make dmg
```

This writes `dist/3F.dmg`.

## Public distribution

The default build uses an ad-hoc signature, which is appropriate only for a
local build. Do not distribute that DMG from a website. For a public release,
sign it with a Developer ID certificate, enable the hardened runtime (handled
by the build script for a Developer ID identity), and notarize the DMG:

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' make dmg
xcrun notarytool submit dist/3F.dmg \
  --keychain-profile 'notary-profile' --wait
xcrun stapler staple dist/3F.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 dist/3F.dmg
```

The Developer ID certificate and `notary-profile` must belong to the release
publisher. Publish a SHA-256 checksum alongside every DMG, retain the source
and release tag that produced it, and test the stapled DMG on a clean Mac.
Notarization is a security check, not a guarantee that an unsupported private
framework will keep working in future macOS releases.

## Install from the DMG

1. Double-click `dist/3F.dmg`.
2. Drag `3F.app` onto the `Applications` shortcut shown in
   the disk-image window. Running the app directly from the DMG does not install it.
3. Eject the `3F` disk image, then open **Applications → 3F**.
4. If macOS blocks the first launch, Control-click the app in Finder and choose
   **Open**. Allow **Accessibility** access when prompted.
5. A status window opens on launch. It shows whether the engine is running,
   Accessibility permission, received input frames, active fingers, and generated
   middle clicks. It also provides **Enabled**, **Middle-button swipe: Mission
   Control**, **Middle-button click: Auto Scroll**, and **Launch at Login** controls.
6. Closing the window leaves the app running. Reopen it from the `3F` item in
   the upper-right menu bar. The Dock icon is hidden by default; toggle
   **Show Dock Icon** in the `3F` menu if you want it visible.

### If Accessibility permission does not work

If 3F is running but does not generate middle clicks, reset its Accessibility
entry instead of only toggling the switch:

1. Quit 3F.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Select `3F`, click the **−** button to remove it completely, then click
   **+** and select the installed `3F.app` again.
4. Relaunch 3F and confirm that Accessibility shows **Allowed** in the status
   window.

## Development checks

```sh
make test
swiftc -parse-as-library -typecheck -target arm64-apple-macos13.0 macos/ThreeFingerMiddleClickApp.swift
```

The gesture thresholds are intentionally fixed source constants in
`src/gesture.rs`.

If Swift reports that its SDK and compiler versions do not match, install or
select a matching Xcode / Command Line Tools pair before building the app.

## License

This project is released under the [MIT License](LICENSE). It does not bundle
Apple frameworks or Apple source code. If you contribute code or assets copied
from elsewhere, you are responsible for preserving their required notices and
licenses.

## Development assistance

This project was created with assistance from GPT-5.6 Sol and GPT-5.6 Terra.

---

## 한국어 안내

3F는 내장 트랙패드의 **세 손가락 탭 또는 물리 클릭**을 마우스 가운데
클릭(휠 클릭)으로 바꾸고, **마우스 가운데 버튼 위쪽 제스처**로 Mission
Control을 여는 개인용 macOS 유틸리티입니다. 대화형 컨트롤이 아닌 곳에서 물리
마우스 가운데 버튼을 클릭하면 Windows 방식 자동 스크롤을 시작합니다.

### 기능

- 런타임에 `MultitouchSupport.framework`를 열어 트랙패드 터치 프레임을
  감지합니다.
- 정확히 세 손가락으로 220ms 안에 끝나는 탭만 인식합니다. 손가락이
  떨어지는 시간차는 최대 80ms, 중심점 이동은 최대 `0.020`이며 네 번째
  손가락이 닿으면 제스처를 취소합니다.
- 세 손가락으로 트랙패드를 실제로 누르면 원래 좌클릭을 막고 가운데
  버튼 down/up 이벤트로 바꿉니다.
- 현재 커서 위치에 Core Graphics 가운데 클릭을 전송합니다.
- 마우스 가운데 버튼을 누른 채 위로 80pt 이상 움직이면 Mission Control을
  열고, 좌/우로 80pt 이상 움직이면 트랙패드처럼 데스크탑 화면(Spaces)을
  전환합니다 (왼쪽 드래그 시 다음 데스크탑, 오른쪽 드래그 시 이전 데스크탑).
  커서는 이동한 위치에 그대로 둡니다. 손쉬운 사용 API에서 대화형
  컨트롤로 확인되는 위치의 8pt 이내 클릭은 일반 가운데 클릭으로 유지됩니다.
- 그 밖의 위치에서 물리 가운데 버튼을 클릭하면 사방향 기준점이 나타납니다.
  포인터를 기준점의 12pt 데드존 밖으로 움직이면 멀어질수록 더 빠르게 포인터
  이동의 반대 방향으로 상하 스크롤하고 같은 방향으로 좌우 스크롤하며, 아무
  마우스 버튼이나 Escape를 누르면 종료됩니다. 일반 텍스트를 포함해 손쉬운
  사용 API에서 비대화형 콘텐츠로 확인되는 위치에서 시작할 수 있습니다. 링크,
  탭, 버튼 등 누를 수 있는 컨트롤에서는 원래 가운데 클릭을 유지합니다. 앱이
  클릭 대상을 제공하지 않으면 3F는 원래 가운데 클릭을 유지합니다.
- 메뉴 막대에서 **Enabled**, 마우스 제스처, 자동 스크롤,
  **Launch at Login**, **Quit**을 제공합니다.

`MultitouchSupport`는 macOS의 비공개 프레임워크입니다. 이 앱은 개인용을
목적으로 하며, macOS 업데이트 뒤에 동작이 달라지거나 중단될 수 있습니다.

### 개인정보 및 보안

- **Enabled** 상태일 때만 원시 트랙패드 접촉 프레임을 읽습니다. 전역
  마우스 이벤트 필터도 입력 기능이 실행 중일 때만 설치하며, 비활성화하거나
  앱을 종료하면 제거합니다. 트랙패드가 없어도 마우스 기능은 독립적으로
  사용할 수 있습니다. 키보드 입력은 변경 없이 통과시키며 자동 스크롤 중
  Escape인지 여부만 확인합니다.
- 접촉 좌표, 마우스 이벤트, 진단 정보는 파일에 기록하거나 네트워크로
  전송하지 않습니다. Enabled/마우스 제스처/자동 스크롤/Dock 아이콘 설정과
  상태 창에 표시할 집계 진단값만 저장합니다.
- 이 앱은 해당 마우스 이벤트를 막고 대체 입력을 전송하므로 손쉬운 사용
  권한이 필요합니다. 권한의 용도를 확인한 뒤 허용하고, 사용하지 않을 때는
  앱을 비활성화하세요.
- 비공개·미지원 프레임워크에 의존하므로 Mac App Store 배포용이 아니며,
  Apple이 동작 지속성을 보장하지 않습니다.

3F는 Apple과 제휴하거나 Apple의 보증 또는 지원을 받는 소프트웨어가
아닙니다.

### 빌드

필요 사항: Xcode Command Line Tools, Rust, macOS 13 이상을 실행하는
Apple Silicon Mac.

```sh
brew install rust
make app
open dist/3F.app
```

완성된 앱은 `dist/3F.app`에 생성됩니다. 처음 실행하면 macOS가 손쉬운
사용 권한을 요청합니다. 가운데 클릭을 전송할 수 있도록 **시스템 설정 →
개인정보 보호 및 보안 → 손쉬운 사용**에서 허용하세요.

보관하거나 옮길 용도의 압축 디스크 이미지는 다음으로 만듭니다.

```sh
make dmg
```

결과 파일은 `dist/3F.dmg`입니다.

### DMG 설치

1. `dist/3F.dmg`를 이중 클릭합니다.
2. 디스크 이미지 창의 `3F.app`을 `Applications` 바로 가기로 드래그합니다.
   DMG 안에서 직접 실행하는 것은 설치가 아닙니다.
3. `3F` 디스크 이미지를 추출한 뒤 **응용 프로그램 → 3F**를 실행합니다.
4. macOS가 첫 실행을 막으면 Finder에서 앱을 Control-클릭하고 **열기**를
   선택한 다음, 손쉬운 사용 권한을 허용합니다.
5. 상태 창에서 엔진 실행 상태, 손쉬운 사용 권한, 수신된 입력 프레임,
   활성 손가락 수, 생성된 가운데 클릭 수를 확인하고 **Enabled**,
   **Middle-button swipe: Mission Control**, **Middle-button swipe: Switch Desktops**,
   **Launch at Login**을 제어할 수 있습니다. **Middle-button click: Auto Scroll**로
   자동 스크롤도 켜거나 끌 수 있습니다.
6. 창을 닫아도 앱은 계속 실행됩니다. 화면 오른쪽 상단의 `3F` 메뉴 막대
   항목으로 다시 열 수 있습니다. Dock 아이콘은 기본적으로 숨겨져 있으며,
   필요하면 `3F` 메뉴에서 **Show Dock Icon**을 켜세요.

### 손쉬운 사용 권한이 작동하지 않을 때

3F가 실행 중인데도 가운데 클릭이 생성되지 않으면, 단순히 토글만 바꾸지
말고 손쉬운 사용 목록의 항목을 재등록하세요.

1. 3F를 종료합니다.
2. **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**을 엽니다.
3. `3F`를 선택하고 **−** 버튼으로 완전히 제거합니다. 이어서 **+** 버튼을
   눌러 설치된 `3F.app`을 다시 추가합니다.
4. 3F를 다시 실행하고 상태 창에 Accessibility가 **Allowed**로 표시되는지
   확인합니다.

### 공개 배포

기본 빌드는 로컬 용도의 ad-hoc 서명을 사용합니다. 이 DMG는 웹사이트에
배포하지 마세요. 공개 배포에는 Developer ID 인증서로 서명하고,
Hardened Runtime을 활성화한 뒤(Developer ID identity를 쓸 때 빌드 스크립트가
처리함) DMG를 공증해야 합니다.

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' make dmg
xcrun notarytool submit dist/3F.dmg \
  --keychain-profile 'notary-profile' --wait
xcrun stapler staple dist/3F.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 dist/3F.dmg
```

Developer ID 인증서와 `notary-profile`은 배포자의 것이어야 합니다. DMG마다
SHA-256 체크섬을 함께 공개하고, 해당 DMG를 만든 소스와 릴리스 태그를
보관하며, 공증 티켓을 붙인 DMG는 깨끗한 Mac에서도 테스트하세요. 공증은
보안 검사일 뿐 비공개 프레임워크가 향후 macOS에서도 계속 동작한다는 보장은
아닙니다.

### 개발 확인

```sh
make test
swiftc -parse-as-library -typecheck -target arm64-apple-macos13.0 macos/ThreeFingerMiddleClickApp.swift
```

제스처 임계값은 의도적으로 `src/gesture.rs`의 고정 소스 상수로 두었습니다.
Swift에서 SDK와 컴파일러 버전이 맞지 않는다고
보고하면, 일치하는 Xcode 또는 Command Line Tools 조합을 설치하거나 선택하세요.

### 라이선스

이 프로젝트는 [MIT License](LICENSE)로 배포됩니다. Apple 프레임워크나 Apple
소스 코드를 포함하지 않습니다. 외부에서 가져온 코드나 자산을 기여할 경우,
필요한 고지와 라이선스를 보존할 책임은 기여자에게 있습니다.

### 제작

이 프로젝트는 GPT-5.6 Sol과 GPT-5.6 Terra의 도움을 받아 제작되었습니다.
