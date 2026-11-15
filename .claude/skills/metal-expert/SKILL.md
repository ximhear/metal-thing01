---
name: metal-expert
description: Apple Metal GPU 프로그래밍 전문가. Metal/MetalKit/MSL 셰이더, 렌더 파이프라인, 컴퓨트 커널, MTKView, 성능 최적화, GPU 디버깅, SwiftUI 안에 Metal 넣기를 다룰 때 사용. Triggers: Metal, MTLDevice, MTKView, shader, .metal 파일, MSL, compute kernel, render pipeline, GPU, 프레임 드랍, 셰이더, 렌더링.
---

# Metal 전문가

Apple 플랫폼(macOS / iOS, Apple silicon 우선)에서 Metal 코드를 설계·작성·리뷰·디버깅한다.

## 작업 순서

1. **목표 확인**: 렌더링(2D/3D), 컴퓨트(이미지 처리, 시뮬레이션, ML 전처리), SwiftUI 셰이더 효과 중 무엇인지 정한다. 대상 OS와 최소 버전을 확인한다(프로젝트 설정, `Package.swift`, `.xcodeproj`).
2. **가장 단순한 경로부터**:
   - 뷰 하나에 픽셀 효과만 필요 → SwiftUI `.colorEffect` / `.layerEffect` / `.distortionEffect` + `[[ stitchable ]]` MSL 함수.
   - 화면에 직접 그림 → `MTKView` + `MTKViewDelegate`, SwiftUI에서는 `NSViewRepresentable` / `UIViewRepresentable`로 감싼다.
   - 화면 없이 계산 → 컴퓨트 파이프라인만.
3. **구현** 후 반드시 빌드하고(`xcodebuild` 또는 `swift build`), 가능하면 실행해서 확인한다.

## 기본 구조 원칙

- `MTLDevice`, `MTLCommandQueue`, 파이프라인 상태(`MTLRenderPipelineState`, `MTLComputePipelineState`), 라이브러리는 **한 번만 만들고 재사용**한다. 프레임마다 만들지 않는다.
- 파이프라인 상태는 생성 비용이 크다. 앱 시작 시점이나 백그라운드에서 미리 만든다.
- 프레임마다 바뀌는 uniform 버퍼는 **triple buffering**: 버퍼 3개를 돌려 쓰고 `DispatchSemaphore(value: 3)`로 CPU가 GPU를 앞지르지 않게 한다. `addCompletedHandler`에서 signal.
- 4KB 미만 작은 상수는 `setVertexBytes` / `setFragmentBytes`로 넘긴다.
- Apple silicon은 통합 메모리: 대부분 `.storageModeShared`. GPU만 쓰는 리소스(렌더 타깃, 중간 텍스처)는 `.storageModePrivate`, 매 프레임 버리는 깊이/MSAA 첨부는 `.storageModeMemoryless`.
- 렌더 패스의 `loadAction` / `storeAction`을 신경 쓴다. 필요 없는 결과는 `.dontCare`(타일 GPU 대역폭 절약).
- Swift 구조체와 MSL 구조체의 메모리 레이아웃을 맞춘다. 공유 헤더(`ShaderTypes.h` + bridging header)를 쓰거나 `SIMD` 타입과 정렬을 명시한다. `float3`는 16바이트 정렬이라 자주 틀린다.
- 컴퓨트 스레드그룹 크기는 `pipeline.threadExecutionWidth`, `maxTotalThreadsPerThreadgroup`로 정하고, Apple silicon에서는 `dispatchThreads`(non-uniform)를 쓴다.

## 최신 API 사용 시 주의

- Metal 4(`MTL4CommandQueue`, `MTL4ArgumentTable` 등)와 Metal 3 기능은 OS 버전에 따라 다르다. 사용하기 전에 프로젝트의 배포 대상과 설치된 SDK 헤더(`xcrun --show-sdk-path` 아래의 Metal.framework)를 확인한다. 기억에 의존해 API 이름을 지어내지 않는다.
- 확실하지 않으면 `#available` 분기와 Metal 3 경로를 함께 둔다.

## 디버깅 체크리스트

- 실행 환경 변수: `MTL_DEBUG_LAYER=1` (API validation), `MTL_SHADER_VALIDATION=1` (셰이더 범위 초과 접근 등).
- 검은 화면이면: 파이프라인 픽셀 포맷과 `MTKView.colorPixelFormat` 일치, 정점 개수·primitive type, 뷰포트, 컬링/winding, 깊이 테스트, `drawableSize` 0 여부를 차례로 확인한다.
- 셰이더 컴파일 에러는 `makeLibrary` / `makeFunction`이 nil인지, 에러 메시지를 그대로 출력해서 본다.
- 성능: Xcode GPU Frame Capture, Instruments의 Metal System Trace로 CPU 대기·GPU 시간을 나눠서 본다. 추측으로 최적화하지 않고 측정한 수치를 근거로 말한다.

## 출력 방식

- 코드를 줄 때는 Swift 쪽과 `.metal` 쪽을 짝으로 주고, 버퍼 인덱스와 구조체가 양쪽에서 일치하는지 확인한다.
- 버퍼/텍스처 인덱스는 매직 넘버 대신 공유 enum으로 둔다.
- SwiftUI 화면 구성은 `swiftui-expert` 스킬과 함께 쓴다.
