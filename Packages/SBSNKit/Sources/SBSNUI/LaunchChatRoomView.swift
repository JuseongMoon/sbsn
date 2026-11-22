#if os(iOS)
import PhotosUI
import SBSNBackend
import SBSNCore
import SwiftUI
import UIKit

/// 출시 2단계 대화방(설계 2.4, 두 앱 공통). 고객·작가 쌍마다 방 하나이고 메시지는 마지막 활동 뒤 30일 남는다(L18).
///
/// - 송신은 서버 함수다. 보내기 전에 `ContactFilter`가 연락처·링크를 찾으면 "고치기 / 가리고 보내기"를 고르게 한다(L03).
/// - 사진은 한 장씩, 긴 변 1,280px로 줄여 메타데이터 없이 JPEG로 다시 만든 뒤 보낸다(L19, 서버도 다시 검사한다).
/// - 시스템 메시지(신청·수락·거절·만료·시작·종료·취소·연장)는 서버가 넣는다. 가운데 회색 줄로 그린다(W12).
/// - 화면에 보인 상대 메시지까지 읽음으로 둔다.
/// - `top`은 방 위(신청 대기·티켓 막대), `bottom`은 입력창 위(고객 신청 막대·작가 신청 카드)에 앱이 넣는다.
public struct LaunchChatRoomView<Top: View, Bottom: View>: View {
    let roomId: String
    let myUid: String
    let counterpartName: String
    let top: Top
    let bottom: Bottom

    @State private var messages: [LaunchMatch.Message] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var contactWarning: ContactFilter.Result?
    @State private var photoItem: PhotosPickerItem?
    @State private var lastMarkedRead: String?
    @State private var fullScreenPhoto: String?

    public init(roomId: String, myUid: String, counterpartName: String,
                @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.roomId = roomId
        self.myUid = myUid
        self.counterpartName = counterpartName
        self.top = top()
        self.bottom = bottom()
    }

    public var body: some View {
        VStack(spacing: 0) {
            top
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        Text("메시지는 마지막 촬영(또는 대화) 뒤 30일 동안 보관됩니다")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .accessibilityIdentifier("chat.retention")
                        if messages.isEmpty {
                            Text("\(counterpartName)에게 먼저 인사해 보세요.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                        }
                        ForEach(messages) { message in
                            row(message).id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            bottom
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("chat.error")
            }
            inputBar
        }
        .task(id: roomId) { await listen() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await sendPhoto(item) }
        }
        .sheet(item: Binding(get: { contactWarning.map(ContactWarning.init) }, set: { if $0 == nil { contactWarning = nil } })) { warning in
            contactSheet(warning.result)
                .presentationDetents([.height(260)])
        }
        .fullScreenCover(item: Binding(get: { fullScreenPhoto.map(PhotoPath.init) }, set: { fullScreenPhoto = $0?.path })) { photo in
            LaunchChatPhotoViewer(path: photo.path) { fullScreenPhoto = nil }
        }
    }

    // MARK: - 말풍선

    @ViewBuilder
    private func row(_ message: LaunchMatch.Message) -> some View {
        switch message.kind {
        case .system:
            Text(message.text ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .accessibilityIdentifier("chat.system")
        case .text, .photo:
            let mine = message.senderUid == myUid
            HStack {
                if mine { Spacer(minLength: 48) }
                Group {
                    if message.kind == .photo, let path = message.attachmentPath {
                        LaunchChatPhotoThumbnail(path: path)
                            .onTapGesture { fullScreenPhoto = path }
                    } else {
                        Text(message.text ?? "")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(mine ? Color.accentColor : Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(mine ? .white : .primary)
                    }
                }
                .accessibilityIdentifier(mine ? "chat.mine" : "chat.theirs")
                if !mine { Spacer(minLength: 48) }
            }
        }
    }

    // MARK: - 입력

    private var inputBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "plus.circle")
                    .font(.title2)
            }
            .disabled(isSending)
            .accessibilityLabel("사진 보내기")
            .accessibilityIdentifier("chat.photo")
            TextField("메시지 입력", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("chat.input")
            Button("보내기") { trySend() }
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("chat.send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func contactSheet(_ result: ContactFilter.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("연락처나 링크가 들어 있어요")
                .font(.headline)
            Text("운영정책상 보낼 수 없어요. 고쳐서 보내거나 가린 채로 보내 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(result.masked)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("chat.contactPreview")
            HStack {
                Button("고치기") { contactWarning = nil }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("chat.contactFix")
                Spacer()
                Button("가리고 보내기") {
                    let masked = result.masked
                    contactWarning = nil
                    Task { await send(masked) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("chat.contactMask")
            }
        }
        .padding(20)
    }

    private func trySend() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let found = ContactFilter.scan(text) {
            contactWarning = found
            return
        }
        Task { await send(text) }
    }

    private func send(_ text: String) async {
        guard [Character](text).count <= ChatMessage.textLimit else {
            errorMessage = "메시지는 1,000자까지 보낼 수 있어요."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            try await LaunchMatchService.send(roomId: roomId, clientRequestId: Self.newRequestId(), text: text)
            draft = ""
            errorMessage = nil
        } catch {
            errorMessage = "보내지 못했어요: \(error.localizedDescription)"
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        isSending = true
        defer { isSending = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let jpeg = Self.chatJPEG(from: data) else {
                errorMessage = "사진을 읽지 못했어요."
                return
            }
            try await LaunchMatchService.sendPhoto(roomId: roomId, clientRequestId: Self.newRequestId(), jpeg: jpeg)
            errorMessage = nil
        } catch {
            errorMessage = "사진을 보내지 못했어요: \(error.localizedDescription)"
        }
    }

    /// 긴 변 1,280px, 메타데이터(GPS 포함) 없는 JPEG(품질 0.8, Android와 같은 값, L19)
    static func chatJPEG(from data: Data, longSide: CGFloat = 1280) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, longSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // 픽셀만 다시 그려 원본 EXIF·GPS가 따라오지 않는다.
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.jpegData(compressionQuality: 0.8)
    }

    static func newRequestId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - 듣기·읽음

    private func listen() async {
        do {
            for try await list in LaunchMatchService.messages(roomId: roomId) {
                messages = list
                await markRead()
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "대화를 불러오지 못했어요: \(error.localizedDescription)"
        }
    }

    private func markRead() async {
        guard let last = messages.last(where: { $0.kind != .system && $0.senderUid != nil && $0.senderUid != myUid }),
              last.id != lastMarkedRead else { return }
        lastMarkedRead = last.id
        try? await LaunchMatchService.markRead(roomId: roomId, throughMessageId: last.id)
    }

    private struct ContactWarning: Identifiable {
        let result: ContactFilter.Result
        var id: String { result.masked }
    }

    private struct PhotoPath: Identifiable {
        let path: String
        var id: String { path }
    }
}

/// 사진 말풍선(인증 SDK로 읽는다)
struct LaunchChatPhotoThumbnail: View {
    let path: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: 180, height: 180)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task(id: path) {
            do {
                image = UIImage(data: try await LaunchMatchService.attachmentData(path: path))
            } catch {
                failed = true
            }
        }
    }
}

/// 사진 전체 화면
struct LaunchChatPhotoViewer: View {
    let path: String
    let onClose: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
            Button("닫기", action: onClose)
                .buttonStyle(.borderedProminent)
                .padding()
                .accessibilityIdentifier("chat.photoClose")
        }
        .task(id: path) {
            image = (try? await LaunchMatchService.attachmentData(path: path)).flatMap(UIImage.init(data:))
        }
    }
}
#endif
