import GeoshopCore
import SwiftUI

/// 도움말 창 (Help ▸ Geoshop 도움말, ⌘?).
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Geoshop 도움말").font(.largeTitle.weight(.bold))
                    Text("GPX 기록을 기준으로 사진의 촬영일시와 위치를 고칩니다.")
                        .foregroundStyle(.secondary)
                }

                HelpSection(title: "시작하기", systemImage: "1.circle") {
                    Step("새 프로젝트(⌘N)를 만들고 GPX 파일을 하나 이상 고릅니다. 시각 정보가 있는 트랙이어야 합니다.")
                    Step("사진 소스를 고릅니다. ‘사진 앱 보관함’은 보관함의 촬영일·위치만 바꾸고, ‘파일’은 사진 파일의 EXIF를 직접 고칩니다. 나중에 바꿀 수 없습니다.")
                    Step("‘사진 추가…’로 사진을 넣습니다. 원본은 옮기지 않고 참조만 저장합니다. 파일 소스는 폴더째 넣거나 끌어다 놓아도 됩니다.")
                    Step("사진을 고르고 지도나 고도표를 클릭해 시각·위치를 할당합니다.")
                    Step("툴바의 ‘일괄 적용’으로 사진에 반영합니다.")
                }

                HelpSection(title: "할당", systemImage: "hand.tap") {
                    Bullet("지도에서는 클릭한 곳에서 가장 가까운 트랙 위 지점으로 맞춰집니다. 트랙에서 너무 먼 곳은 무시합니다.")
                    Bullet("왕복 코스처럼 같은 곳을 여러 번 지났다면 시각 후보 목록이 뜹니다. 후보에 마우스를 올리면 고도표에서 위치를 확인할 수 있습니다.")
                    Bullet("고도표는 가로축을 거리 또는 시간으로 바꿀 수 있습니다. 여러 GPX 사이의 기록 없는 구간은 선이 끊깁니다.")
                    Bullet("여러 장을 고른 채 클릭하면 모두 같은 시각·위치를 받습니다.")
                    Bullet("할당은 적용 전까지 앱 안에만 저장됩니다. 지도 위 카메라 표시를 누르면 그 지점에 할당된 사진이 선택됩니다.")
                }

                HelpSection(title: "일괄 적용", systemImage: "square.and.arrow.down.on.square") {
                    Bullet("적용 전 확인 화면에서 사진별로 바뀌는 값을 확인할 수 있습니다.")
                    Bullet("파일 소스: 이미지는 다시 압축하지 않고 촬영일시(원본·디지털화), 시간대 오프셋, GPS 위치·고도만 바꿉니다. 파일의 생성·수정일은 그대로입니다. 원본에 바로 덮어쓰며 되돌릴 수 없습니다.")
                    Bullet("보관함 소스: 사진 앱의 ‘날짜 및 시간 조정’, ‘위치 조정’과 같은 방식입니다. 원본 파일은 그대로라서 사진 앱에서 ‘수정되지 않은 원본’으로 내보내면 원래 값이 나옵니다. 일반 내보내기에는 바뀐 값이 들어갑니다.")
                    Bullet("실패한 사진은 할당이 남아 있어 다시 적용할 수 있습니다.")
                    Bullet("지원 형식(파일): JPEG, HEIC, PNG, TIFF. RAW·DNG와 동영상은 지원하지 않습니다.")
                }

                HelpSection(title: "시간대", systemImage: "globe.asia.australia") {
                    Bullet("GPX 시각은 UTC입니다. 프로젝트를 만들 때 첫 트랙 위치로 현지 시간대를 정하고, 프로젝트 정보에서 바꿀 수 있습니다.")
                    Bullet("파일 소스는 이 시간대의 현지 시각과 오프셋(예: +09:00)을 함께 기록합니다.")
                    Bullet("한 프로젝트는 시간대 하나를 씁니다. 시간대가 다른 여행은 프로젝트를 나누세요.")
                }

                HelpSection(title: "사진 상태", systemImage: "circle.badge.questionmark") {
                    StatusRow(status: .pending, text: "할당됨, 적용 대기")
                    StatusRow(status: .applied, text: "적용됨")
                    StatusRow(status: .failed(""), text: "적용 실패 (마우스를 올리면 사유)")
                    StatusRow(status: .missing, text: "찾을 수 없음 — 파일은 우클릭 ▸ 다시 연결")
                    StatusRow(status: .unsupported, text: "지원하지 않는 형식")
                    StatusRow(status: .notEditable, text: "편집할 수 없는 보관함 사진 (공유 앨범 등)")
                }

                HelpSection(title: "단축키", systemImage: "keyboard") {
                    Shortcut(keys: "⌘N", text: "새 프로젝트")
                    Shortcut(keys: "클릭 / ⌘클릭 / ⇧클릭", text: "사진 선택 / 추가·빼기 / 범위")
                    Shortcut(keys: "⌘A", text: "사진 모두 선택 (그리드에서)")
                    Shortcut(keys: "Delete", text: "선택한 사진 할당 해제 (그리드에서)")
                    Shortcut(keys: "Esc", text: "선택 해제")
                    Shortcut(keys: "⌘Z / ⇧⌘Z", text: "할당 실행 취소 / 다시 실행")
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) { content }
                .padding(.leading, 4)
        }
    }
}

private struct Step: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "arrow.right.circle").foregroundStyle(.secondary) }
    }
}

private struct Bullet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusRow: View {
    let status: PhotoStatus
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            StatusBadge(status: status).frame(width: 20)
            Text(text)
        }
    }
}

private struct Shortcut: View {
    let keys: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.callout.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(text)
        }
    }
}

/// Help 메뉴 항목.
struct HelpCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Geoshop 도움말") { openWindow(id: HelpView.windowID) }
            .keyboardShortcut("?", modifiers: .command)
    }
}

extension HelpView {
    static let windowID = "help"
}
