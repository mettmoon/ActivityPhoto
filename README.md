# Geoshop

GPX 트랙을 기준으로 사진의 촬영일시와 위치를 고치는 Mac 앱. 기획은 [docs/PRD.md](docs/PRD.md).

## 구조

| 경로 | 내용 |
|------|------|
| `ActivityPhoto/` | macOS 앱 (SwiftUI). Xcode 타깃 이름은 `ActivityPhoto`, 표시 이름은 Geoshop |
| `GeoshopCore/` | UI와 무관한 로직 (로컬 Swift 패키지): GPX 파싱, 트랙 타임라인·보간·스냅, SwiftData 모델, 프로젝트 저장소, EXIF 읽기·쓰기 |
| `docs/PRD.md` | 기획서 |

## 빌드·테스트

```bash
open ActivityPhoto.xcodeproj
```

```bash
swift test --package-path GeoshopCore
```

macOS 27, Xcode 27.2 이상.

## 데모 모드 (Debug 빌드 전용)

메모리 저장소에 가짜 GPX 2개(순환·왕복 코스)와 상태별 사진으로 프로젝트를 만든다. 실제 저장소는 건드리지 않는다.

- Xcode: Scheme ▸ Edit Scheme ▸ Run ▸ Arguments에 `-GeoshopDemo` 추가
- `-GeoshopDemo -GeoshopDemoAutoApply`: 대기 중 사진을 샌드박스 안에서 파일에 적용하고 결과를 출력한 뒤 종료 (파일 쓰기 경로 확인용)
