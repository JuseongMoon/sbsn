import PhotosUI
import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI
import UIKit

/// 제재 배너(설계 2.3, L16·L17): 최근 7일 응답 없이 만료된 신청 2회째 경고, 제한 중이면 끝 시각과 [검토 요청].
struct PhotographerSanctionSection: View {
    @Environment(PhotographerLaunchModel.self) private var launch
    @State private var showsReview = false

    var body: some View {
        if let status = launch.sanction {
            if status.isRestricted(), let until = status.restrictedUntil {
                Section {
                    Label("\(LaunchTime.clock(until))까지 새 신청 제한 · 고객 지도에서 숨겨져요. 확정된 촬영과 채팅은 그대로예요",
                          systemImage: "hand.raised.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("sanction.limited")
                    if let reviewStatus = launch.reviewStatus {
                        Text(reviewStatus).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("sanction.reviewStatus")
                    } else {
                        Button("검토 요청") { showsReview = true }
                            .accessibilityIdentifier("sanction.review")
                    }
                }
                .sheet(isPresented: $showsReview) { SanctionReviewSheet() }
            } else if status.missedCount7d >= 2 {
                Section {
                    Label("최근 7일 응답 없이 만료 \(status.missedCount7d)회: 한 번 더 놓치면 30분 동안 새 신청을 받지 못해요",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("sanction.warning")
                }
            }
        }
    }
}

/// 검토 요청(L17): 메모 한 칸 → 보내기 → "검토 중 · 영업일 3일 안에 답드려요"
struct SanctionReviewSheet: View {
    @Environment(PhotographerLaunchModel.self) private var launch
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var clientRequestId = UUID().uuidString.lowercased()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("어떤 상황이었는지 적어 주세요", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("sanction.review.note")
                } footer: {
                    // 서버와 같은 코드포인트로 센다(500, LaunchText)
                    Text("\(LaunchText.length(note))/500 · 영업일 3일 안에 답드려요. 잘못된 제한이면 기록을 지우고 집계를 다시 계산해요.")
                        .accessibilityIdentifier("sanction.review.count")
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("검토 요청")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("보내기") { Task { await send() } }
                        .disabled(isSending || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || LaunchText.length(note) > 500)
                        .accessibilityIdentifier("sanction.review.send")
                }
            }
        }
    }

    private func send() async {
        guard let uid = launch.uid else { return }
        isSending = true
        defer { isSending = false }
        do {
            guard let eventId = try await LaunchArtistProfileService.latestSanctionEventId(uid: uid) else {
                error = "검토할 제재 내역이 없어요."
                return
            }
            try await LaunchArtistProfileService.requestReview(eventId: eventId, note: note, clientRequestId: clientRequestId)
            launch.reviewStatus = "검토 중 · 영업일 3일 안에 답드려요"
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 작가 프로필 편집(마이 → 프로필, W9): 추천 촬영 시간, 소개(500자), 사진. 닉네임은 로그인 때 정한 값을 쓴다.
struct PhotographerProfileEditor: View {
    @Environment(PhotographerLaunchModel.self) private var launch
    @State private var minutes = 20
    @State private var bio = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoJPEG: Data?
    @State private var currentPhoto: UIImage?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if let photoJPEG, let image = UIImage(data: photoJPEG) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else if let currentPhoto {
                            Image(uiImage: currentPhoto).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle").resizable().foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    PhotosPicker("사진 고르기", selection: $photoItem, matching: .images)
                        .accessibilityIdentifier("profile.photo")
                }
            }
            Section("추천 촬영 시간") {
                Stepper("\(minutes)분", value: $minutes, in: LaunchMatch.minutesRange, step: LaunchMatch.minutesStep)
                    .accessibilityIdentifier("profile.minutes")
            }
            Section {
                TextField("어떤 촬영을 하는지 적어 주세요", text: $bio, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("profile.bio")
            } header: {
                Text("소개")
            } footer: {
                Text("\(LaunchText.length(bio))/500 · 고객이 지도 카드의 프로필에서 봐요")
            }
            if let message {
                Text(message).font(.footnote).accessibilityIdentifier("profile.message")
            }
        }
        .navigationTitle("프로필")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") { Task { await save() } }
                    .disabled(isSaving || isLoading || LaunchText.length(bio) > 500)
                    .accessibilityIdentifier("profile.save")
            }
        }
        .task { await load() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoJPEG = LaunchImageEncoding.jpeg(from: data, longSide: 1080)
                }
            }
        }
    }

    private func load() async {
        defer { isLoading = false }
        guard let uid = launch.uid, let profile = try? await LaunchArtistProfileService.profile(artistUid: uid) else { return }
        minutes = profile.recommendedShootMinutes ?? 20
        bio = profile.bio
        if let path = profile.photoPath, let data = try? await LaunchArtistProfileService.photoData(path: path) {
            currentPhoto = UIImage(data: data)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await LaunchArtistProfileService.save(recommendedShootMinutes: minutes, bio: bio, photoJPEG: photoJPEG)
            message = "저장했어요"
        } catch {
            message = error.localizedDescription
        }
    }
}
