import GeoshopCore
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 프로젝트 사진 그리드 (기획서 §4.2, §4.5, §5).
struct PhotoGridView: View {
    @Bindable var project: Project
    @Bindable var catalog: PhotoCatalog

    @Environment(\.projectStore) private var store
    @State private var isImportingFiles = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var relinkTarget: PhotoRef?
    @State private var notice: String?
    @State private var errorMessage: String?
    @State private var libraryStatus = PhotoLibraryService.shared.authorizationStatus

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 160), spacing: 8)]

    var body: some View {
        let photos = catalog.visiblePhotos(in: project)
        VStack(spacing: 0) {
            header
            Divider()
            if project.sourceKind == .photoLibrary && libraryStatus != .authorized {
                LibraryAccessBanner(status: libraryStatus) { requestLibraryAccess() }
                Divider()
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(photos) { photo in
                        PhotoCell(
                            photo: photo,
                            status: catalog.status(of: photo),
                            timeZone: project.timeZone,
                            fileURL: catalog.fileURLs[photo.id],
                            isSelected: catalog.selection.contains(photo.id)
                        )
                        .onTapGesture {
                            catalog.click(photo, in: photos, modifiers: NSEvent.modifierFlags)
                        }
                        .contextMenu { contextMenu(for: photo) }
                    }
                }
                .padding(10)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture { catalog.clearSelection() }
            .overlay { emptyState(visibleCount: photos.count) }
            .dropDestination(for: URL.self) { urls, _ in
                guard project.sourceKind == .files else { return false }
                addFiles(urls)
                return true
            }
            footer(visibleCount: photos.count)
        }
        .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.image, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): addFiles(urls)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: Binding(get: { relinkTarget != nil }, set: { if !$0 { relinkTarget = nil } }),
            allowedContentTypes: [.image]
        ) { result in
            guard let photo = relinkTarget else { return }
            relinkTarget = nil
            switch result {
            case .success(let url):
                perform { try store?.relink(photo, to: url, in: project) }
                refresh()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            addLibraryItems(items)
            pickerItems = []
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            libraryStatus = PhotoLibraryService.shared.authorizationStatus
            refresh()
        }
        .alert("오류", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 머리·꼬리

    private var header: some View {
        HStack(spacing: 8) {
            addButton
            Spacer()
            Picker("필터", selection: $catalog.filter) {
                ForEach(PhotoCatalog.Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Menu {
                Picker("정렬", selection: $catalog.sortOrder) {
                    ForEach(PhotoCatalog.SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("정렬", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("정렬: \(catalog.sortOrder.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var addButton: some View {
        switch project.sourceKind {
        case .files:
            Button("사진 추가…", systemImage: "plus") { isImportingFiles = true }
                .help("사진 파일이나 폴더를 고르세요. 그리드로 끌어다 놓아도 됩니다.")
        case .photoLibrary:
            PhotosPicker(selection: $pickerItems, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) {
                Label("사진 추가…", systemImage: "plus")
            }
        }
    }

    private func footer(visibleCount: Int) -> some View {
        HStack {
            if let notice {
                Text(notice).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(summary(visibleCount: visibleCount)).foregroundStyle(.secondary)
            }
            Spacer()
            if !catalog.selection.isEmpty {
                Text("\(catalog.selection.count)장 선택").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func summary(visibleCount: Int) -> String {
        let total = project.photos.count
        let pending = project.photos.filter { catalog.status(of: $0) == .pending }.count
        let missing = project.photos.filter { catalog.status(of: $0) == .missing }.count
        var parts = [visibleCount == total ? "\(total)장" : "\(visibleCount) / \(total)장"]
        if pending > 0 { parts.append("대기 \(pending)") }
        if missing > 0 { parts.append("찾을 수 없음 \(missing)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func emptyState(visibleCount: Int) -> some View {
        if project.photos.isEmpty {
            ContentUnavailableView {
                Label("사진 없음", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(project.sourceKind == .files
                     ? "사진 파일이나 폴더를 추가하세요. 원본은 옮기지 않고 참조만 저장합니다."
                     : "사진 보관함에서 사진을 추가하세요. 원본은 옮기지 않고 참조만 저장합니다.")
            }
        } else if visibleCount == 0 {
            ContentUnavailableView("‘\(catalog.filter.title)’ 사진 없음", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - 메뉴

    @ViewBuilder
    private func contextMenu(for photo: PhotoRef) -> some View {
        let targets = catalog.selection.contains(photo.id) ? catalog.selectedPhotos(in: project) : [photo]
        if project.sourceKind == .files && catalog.status(of: photo) == .missing {
            Button("다시 연결…") { relinkTarget = photo }
        }
        if project.sourceKind == .files, let url = catalog.fileURLs[photo.id] {
            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Divider()
        Button(targets.count > 1 ? "목록에서 제거 (\(targets.count)장)" : "목록에서 제거", role: .destructive) {
            perform { try store?.removePhotos(targets, from: project) }
            catalog.selection.subtract(targets.map(\.id))
        }
    }

    // MARK: - 추가

    private func addFiles(_ urls: [URL]) {
        guard let store else { return }
        do {
            let result = try store.addPhotos(fileURLs: urls, to: project)
            showNotice(result)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addLibraryItems(_ items: [PhotosPickerItem]) {
        let identifiers = items.compactMap(\.itemIdentifier)
        Task {
            if !PhotoLibraryService.shared.hasFullAccess {
                libraryStatus = await PhotoLibraryService.shared.requestAccess()
            }
            guard PhotoLibraryService.shared.hasFullAccess else {
                errorMessage = "사진 보관함 전체 접근 권한이 있어야 사진을 추가하고 촬영일·위치를 바꿀 수 있습니다."
                return
            }
            let inputs = PhotoLibraryService.shared.inputs(for: identifiers)
            do {
                var result = try store?.addLibraryPhotos(inputs, to: project) ?? PhotoAddResult()
                result.skipped = Array(repeating: "", count: identifiers.count - inputs.count)
                showNotice(result)
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestLibraryAccess() {
        Task {
            if libraryStatus == .notDetermined {
                libraryStatus = await PhotoLibraryService.shared.requestAccess()
                refresh()
            } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showNotice(_ result: PhotoAddResult) {
        var parts = ["\(result.added)장 추가"]
        if result.duplicates > 0 { parts.append("이미 있는 사진 \(result.duplicates)장 건너뜀") }
        if !result.skipped.isEmpty { parts.append("읽을 수 없는 파일 \(result.skipped.count)개 건너뜀") }
        notice = parts.joined(separator: " · ")
        Task {
            try? await Task.sleep(for: .seconds(5))
            notice = nil
        }
    }

    private func refresh() {
        catalog.refresh(project: project, store: store)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - 셀

private struct PhotoCell: View {
    let photo: PhotoRef
    let status: PhotoStatus
    let timeZone: TimeZone
    let fileURL: URL?
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Color(nsColor: .quaternaryLabelColor)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFill()
                        } else {
                            Image(systemName: status == .missing ? "questionmark.square.dashed" : "photo")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                StatusBadge(status: status)
                    .padding(5)
            }
            .opacity(status.isBlocked ? 0.45 : 1)

            Text(photo.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(caption)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(5)
        .background(isSelected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .help(tooltip)
        .task(id: "\(photo.id)|\(fileURL?.path ?? "")|\(status == .missing)") {
            thumbnail = status == .missing ? nil : await ThumbnailProvider.shared.thumbnail(for: photo, fileURL: fileURL)
        }
    }

    private var caption: String {
        if let assignment = photo.assignment {
            return "→ " + assignment.date.formatted(Date.FormatStyle(date: .numeric, time: .shortened, timeZone: timeZone))
        }
        if let date = photo.originalDate(in: timeZone) {
            return date.formatted(Date.FormatStyle(date: .numeric, time: .shortened, timeZone: timeZone))
        }
        return "촬영일시 없음"
    }

    private var tooltip: String {
        var lines = [photo.fileName, status.description]
        if let date = photo.originalDate(in: timeZone) {
            lines.append("기존 촬영일시: " + date.formatted(in: timeZone))
        } else {
            lines.append("기존 촬영일시: 없음")
        }
        if let lat = photo.originalLatitude, let lon = photo.originalLongitude {
            lines.append(String(format: "기존 위치: %.5f, %.5f", lat, lon))
        } else {
            lines.append("기존 위치: 없음")
        }
        if let path = photo.filePath { lines.append(path) }
        return lines.joined(separator: "\n")
    }
}

/// 상태 배지 (기획서 §4.5).
struct StatusBadge: View {
    let status: PhotoStatus

    var body: some View {
        switch status {
        case .unassigned:
            EmptyView()
        case .pending:
            Circle().fill(.orange).stroke(.white, lineWidth: 1.5).frame(width: 12, height: 12)
        case .applied:
            symbol("checkmark.circle.fill", .white, .green)
        case .failed:
            symbol("exclamationmark.circle.fill", .white, .red)
        case .notEditable:
            symbol("lock.circle.fill", .white, .gray)
        case .unsupported:
            symbol("nosign", .gray, .white)
        case .missing:
            symbol("questionmark.circle.fill", .white, .gray)
        }
    }

    private func symbol(_ name: String, _ primary: Color, _ secondary: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(primary, secondary)
            .shadow(color: .black.opacity(0.3), radius: 1)
    }
}

extension PhotoStatus: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unassigned: "미할당"
        case .pending: "할당됨 (적용 대기)"
        case .applied: "적용됨"
        case .failed(let reason): "실패: \(reason)"
        case .notEditable: "편집 불가 (공유 앨범 등)"
        case .unsupported: "지원하지 않는 형식"
        case .missing: "찾을 수 없음"
        }
    }
}

private struct LibraryAccessBanner: View {
    let status: PHAuthorizationStatus
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(status == .limited
                     ? "사진 보관함 접근이 일부 사진으로 제한되어 있습니다."
                     : "사진 보관함 전체 접근 권한이 필요합니다.")
                    .font(.callout.weight(.semibold))
                Text("촬영일·위치를 바꾸려면 ‘모든 사진’ 접근을 허용해야 합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(status == .notDetermined ? "권한 요청" : "시스템 설정 열기", action: action)
                    .controlSize(.small)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
    }
}
