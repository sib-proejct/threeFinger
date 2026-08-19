# 3F 개인용 초경량 설계서

> 목적: macOS에서 트랙패드 **세 손가락 탭**을 **마우스 가운데 클릭**으로 바꾸는 개인용 유틸리티  
> 구성: **Rust 코어 + 아주 얇은 Swift 메뉴바 앱**  
> 배포: `.app` 중심, 필요하면 `.dmg`로 보관

---

## 1. 목표

기능은 하나만 만든다.

```text
트랙패드 세 손가락 탭
        ↓
Middle Click
```

예:

```text
브라우저 링크 위에서 세 손가락 탭
        ↓
가운데 클릭
        ↓
새 탭에서 열기
```

개인용이므로 다음은 신경 쓰지 않는다.

- App Store 배포
- 자동 업데이트
- 클라우드
- 사용자 계정
- 복잡한 설정창
- 로그 내보내기
- 다중 프로필
- 다양한 제스처
- 일반 사용자용 설치 마법사

---

## 2. 전체 구조

```text
3F.app
│
├─ Swift
│  ├─ 메뉴바 아이콘
│  ├─ Enabled On/Off
│  ├─ Launch at Login
│  └─ Quit
│
└─ Rust
   ├─ 트랙패드 입력 감지
   ├─ 세 손가락 탭 판정
   └─ Middle Click 발생
```

핵심 로직은 전부 Rust에 둔다.

Swift는 macOS 앱 껍데기 역할만 한다.

---

## 3. Rust가 담당하는 것

Rust 코어의 책임:

```text
MultitouchSupport.framework
        ↓
터치 프레임 수신
        ↓
세 손가락인지 확인
        ↓
탭인지 확인
        ↓
CGEvent Middle Click
```

Rust 모듈은 크게 세 개면 충분하다.

```text
src/
├─ lib.rs
├─ multitouch.rs
├─ gesture.rs
└─ mouse.rs
```

### `multitouch.rs`

macOS private framework에서 트랙패드 데이터를 받는다.

### `gesture.rs`

세 손가락 탭인지 판정한다.

### `mouse.rs`

가운데 클릭을 발생시킨다.

---

## 4. Swift가 담당하는 것

Swift 쪽은 최대한 작게 유지한다.

메뉴바:

```text
3F

Enabled            ✓
Launch at Login    ✓
--------------------
Quit
```

필요하면 상태 한 줄만 추가한다.

```text
Status: Running
```

별도 설정창은 만들지 않아도 된다.

---

## 5. Swift ↔ Rust 연결

REST API 같은 통신은 하지 않는다.

같은 앱 안에서 Swift가 Rust 함수를 직접 호출한다.

Rust:

```rust
#[no_mangle]
pub extern "C" fn tmc_start() {
    // 엔진 시작
}

#[no_mangle]
pub extern "C" fn tmc_stop() {
    // 엔진 정지
}
```

Swift:

```swift
tmc_start()
```

또는:

```swift
tmc_stop()
```

이 정도면 충분하다.

Rust는 static library로 빌드한다.

```toml
[lib]
crate-type = ["staticlib"]
```

최종적으로 Swift 앱 실행파일 안에 Rust 코드가 같이 들어간다.

---

## 6. 세 손가락 감지

macOS 공개 API만으로 전역 raw 트랙패드 접촉 정보를 얻기 어렵기 때문에 다음 private framework를 사용한다.

```text
/System/Library/PrivateFrameworks/
MultitouchSupport.framework/MultitouchSupport
```

직접 링크하기보다는 런타임에 연다.

```text
dlopen()
   ↓
dlsym()
   ↓
필요한 함수 가져오기
```

필요한 대표 심볼:

```text
MTDeviceCreateDefault
MTRegisterContactFrameCallback
MTDeviceStart
```

private API이므로 macOS 업데이트 후 깨질 수 있다.

개인용 앱에서는 이 점을 감수한다.

---

## 7. 탭 판정

초기값은 코드에 박아둔다.

```rust
const TAP_TIMEOUT_MS: u64 = 220;
const MAX_MOVEMENT: f32 = 0.020;
const DEBOUNCE_MS: u64 = 180;
```

판정 조건:

```text
정확히 3손가락
    ↓
220ms 안에 끝남
    ↓
손가락 중심 이동량이 작음
    ↓
중간에 4손가락 이상이 되지 않음
    ↓
모두 떨어짐
    ↓
Middle Click
```

초기 버전에서는 GUI에서 수치를 바꾸지 않는다.

불편하면 소스의 상수만 수정하고 다시 빌드한다.

---

## 8. 상태 머신

복잡하게 만들 필요 없다.

```text
Idle
 ↓
3 fingers
 ↓
Tracking
 ├─ 너무 오래 누름 → Cancel
 ├─ 너무 많이 움직임 → Cancel
 ├─ 4 fingers 이상 → Cancel
 └─ 모두 뗌 → Middle Click
                    ↓
                 Debounce
                    ↓
                   Idle
```

Rust 예:

```rust
enum GestureState {
    Idle,

    Tracking {
        started_at: std::time::Instant,
        start_x: f32,
        start_y: f32,
    },

    Debounce {
        until: std::time::Instant,
    },
}
```

---

## 9. 가운데 클릭 발생

가운데 클릭 생성은 macOS Core Graphics 이벤트를 사용한다.

논리적으로:

```text
현재 마우스 위치
      ↓
Middle Mouse Down
      ↓
Middle Mouse Up
```

버튼 번호:

```text
Left   = 0
Right  = 1
Center = 2
```

Rust에서 CoreGraphics C API를 호출하면 된다.

네트워크 요청이 아니기 때문에 반응은 매우 빠르다.

---

## 10. 실제 체감 속도

흐름:

```text
손가락 탭
   ↓
트랙패드 콜백
   ↓
Rust 판정
   ↓
CGEvent
   ↓
대상 앱
```

인터넷이나 서버를 거치지 않는다.

따라서 속도 문제는 거의 없다.

중요한 것은 API 처리 시간이 아니라:

```text
이게 탭인가?
아니면 드래그인가?
```

를 얼마나 잘 구분하느냐이다.

유효한 탭이 끝나는 즉시 Middle Click을 발생시키면 된다.

---

## 11. 권한

Middle Click 이벤트를 다른 앱에 보내기 위해 macOS에서 손쉬운 사용 권한이 필요할 수 있다.

```text
시스템 설정
→ 개인정보 보호 및 보안
→ 손쉬운 사용
→ 3F 허용
```

필요하다면 Input Monitoring 권한도 실제 환경에서 확인한다.

불필요한 권한은 요구하지 않는다.

---

## 12. Launch at Login

이 기능은 Swift에서 처리한다.

메뉴:

```text
Launch at Login ✓
```

켜면 로그인 시 자동 실행된다.

개인용이므로 별도 설정창 없이 메뉴 항목 하나면 충분하다.

---

## 13. 프로젝트 구조

최종 권장 구조:

```text
3F/
│
├─ rust-core/
│  ├─ Cargo.toml
│  └─ src/
│     ├─ lib.rs
│     ├─ multitouch.rs
│     ├─ gesture.rs
│     └─ mouse.rs
│
└─ macos-app/
   ├─ ThreeFingerMiddleClickApp.swift
   ├─ MenuBarController.swift
   └─ RustBridge.h
```

이 이상 쪼개지 않아도 된다.

---

## 14. 개발 순서

### 1단계

Rust CLI에서 트랙패드 입력 확인.

```text
손가락 1개 → 1
손가락 2개 → 2
손가락 3개 → 3
```

여기까지 먼저 성공시킨다.

### 2단계

세 손가락 탭 판정.

```text
three-finger tap
→ accepted
```

드래그:

```text
three-finger drag
→ rejected
```

### 3단계

Middle Click 연결.

```text
three-finger tap
→ middle click
```

브라우저에서 링크가 새 탭으로 열리면 핵심 성공.

### 4단계

Rust 코어를 static library로 변경.

### 5단계

Swift 메뉴바 앱에서:

```text
Enabled
Launch at Login
Quit
```

연결.

### 6단계

`.app` 빌드.

### 7단계

원하면 `.dmg` 생성.

---

## 15. `.app`과 `.dmg`

실제로 앱을 쓰는 데 DMG는 필요 없다.

완성된:

```text
3F.app
```

을:

```text
/Applications
```

에 넣으면 끝이다.

DMG는 보관이나 이동용으로 만들면 된다.

```text
3F.dmg
└─ 3F.app
```

---

## 16. 안 만들 것

v1에서는 다음 기능을 넣지 않는다.

```text
설정창
복잡한 슬라이더
제스처 편집
다른 버튼 매핑
자동 업데이트
Crash reporter
Analytics
Telemetry
클라우드
프로필
앱별 설정
```

필요해지면 나중에 추가한다.

---

## 17. 꼭 신경 쓸 것

딱 세 가지다.

### 1. MultitouchSupport가 Tahoe에서 실제로 동작하는가

가장 먼저 검증해야 한다.

### 2. 세 손가락 드래그를 탭으로 잘못 인식하지 않는가

오탐 방지가 핵심이다.

### 3. Middle Click이 원하는 앱에서 제대로 들어가는가

Safari/Chrome 등 실제 사용 환경에서 확인한다.

---

## 18. 완성 기준

다음만 되면 완성이다.

```text
앱 실행
   ↓
메뉴바에 아이콘 표시
   ↓
세 손가락 탭
   ↓
Middle Click
   ↓
브라우저 링크 새 탭
```

추가로:

```text
Enabled 끄면 동작하지 않음
Launch at Login 동작
앱 재실행해도 정상
```

이면 충분하다.

---

## 19. 최종 구성

```text
                 Swift
             ┌─────────────┐
             │ Menu Bar    │
             │ Enabled     │
             │ Login Item  │
             │ Quit        │
             └──────┬──────┘
                    │
                 C ABI
                    │
                    ▼
                  Rust
        ┌──────────────────────┐
        │ Multitouch Reader    │
        │ Gesture Detector     │
        │ Middle Click Emitter │
        └──────────┬───────────┘
                   │
                   ▼
             macOS CGEvent
                   │
                   ▼
               대상 앱
```

---

## 20. 결론

이 프로젝트는 개인용이므로 크게 만들 필요가 없다.

가장 단순한 목표는:

```text
Rust
= 입력 + 판정 + 클릭

Swift
= 메뉴바 + 실행/종료
```

이다.

먼저 Rust CLI에서 **세 손가락 탭 → Middle Click**만 성공시키고, 그 뒤 Swift 메뉴바 껍데기를 씌운다.

DMG는 가장 마지막에 필요하면 만든다.
