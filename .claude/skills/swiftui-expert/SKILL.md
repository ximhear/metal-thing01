---
name: swiftui-expert
description: SwiftUI 앱 개발 전문가. 화면 구성, 상태 관리(@Observable, @State, @Binding, @Environment), 내비게이션, 애니메이션, 레이아웃, 접근성, Swift Concurrency, Xcode 프로젝트 빌드를 다룰 때 사용. Triggers: SwiftUI, View, @State, @Observable, NavigationStack, iOS 앱, macOS 앱, 화면, UI 만들기, Preview, Xcode.
---

# SwiftUI 전문가

macOS / iOS SwiftUI 앱을 설계·구현·리뷰한다. Apple Human Interface Guidelines를 따르는 자연스러운 앱을 목표로 한다.

## 작업 순서

1. 프로젝트의 배포 대상 OS, Swift 버전, 언어 모드(Swift 6 strict concurrency 여부)를 먼저 확인한다.
2. 화면을 데이터 흐름 관점으로 나눈다: 무엇이 **원천 상태**이고 누가 소유하는지, 어디서 읽기만 하는지.
3. 작은 뷰로 쪼개서 구현하고, 각 뷰에 `#Preview`를 둔다.
4. 빌드해서 경고·에러 없이 통과하는지 확인한다(`xcodebuild -scheme <S> build` 또는 `swift build`). 빌드하지 않은 코드를 "완성"이라고 하지 않는다.

## 상태 관리 원칙 (iOS 17 / macOS 14 이상 기준)

- 모델은 `@Observable` 클래스. `ObservableObject` / `@Published`는 구버전 대응이 필요할 때만.
- 뷰가 소유하는 값·모델: `@State`. 하위 뷰에서 수정: `@Binding` 또는 `@Bindable`.
- 앱 전역 의존성: `@Environment`로 주입. 싱글톤 직접 참조를 피한다.
- 비동기 로딩은 `.task { }` (뷰가 사라지면 자동 취소). `onAppear` 안에서 `Task {}`를 남발하지 않는다.
- UI 상태를 바꾸는 타입은 `@MainActor`. 무거운 작업은 actor나 별도 Task로 분리한다.

## 성능·정확성

- `body`는 가볍게: 정렬·포맷팅·I/O를 `body` 안에서 하지 않는다.
- `ForEach`에는 안정적인 `id`를 쓴다(`\.self`에 가변 값 금지, 인덱스 id 지양).
- 조건부 `if`로 뷰 identity가 바뀌어 상태가 초기화되는 문제를 주의한다. 필요하면 modifier 값만 바꾼다.
- 긴 목록은 `List` 또는 `LazyVStack`.
- 매 프레임 그리는 그래픽은 `Canvas` / `TimelineView`, 더 무거우면 Metal(`metal-expert` 스킬).

## UX 기본

- 내비게이션: `NavigationStack`(단일 흐름), `NavigationSplitView`(macOS·iPad 사이드바).
- 시스템 컴포넌트와 SF Symbols, Dynamic Type, 다크 모드, 시스템 색상을 우선 쓴다. 하드코딩 색·폰트 크기는 피한다.
- 접근성: 아이콘 버튼에 `accessibilityLabel`, 장식 이미지는 숨김, 탭 영역 최소 44pt.
- 빈 상태, 로딩, 에러 상태를 화면마다 정의한다.
- macOS면 메뉴 명령, 키보드 단축키(`.keyboardShortcut`), 창 크기 조절, `Settings` 씬을 챙긴다.

## 출력 방식

- 파일 단위로 코드를 주고, 새 파일이 Xcode 타깃에 포함되는지 확인한다.
- 구버전 API를 쓴다면 이유를 한 줄로 밝힌다.
