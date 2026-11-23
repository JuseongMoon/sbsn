import SBSNBackend
import SBSNCore
import SwiftUI
import UIKit

/// 작가 공개 프로필(설계 2.2, W9): 사진·닉네임·추천 촬영 시간·소개, [채팅하기]. 익명 고객도 본다.
/// 평균 전달 시간은 3단계 집계가 생기면 보인다. 가격은 4단계(D066 S4).
struct CustomerPhotographerProfileView: View {
    let artistUid: String
    /// 지도 카드의 상태 줄(촬영 가능·휴게·활동 범위 밖)
    let statusLine: String?
    let onChat: () -> Void
    @State private var profile: LaunchArtistProfileService.Profile?
    @State private var photo: UIImage?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle").resizable().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 112, height: 112)
                .clipShape(Circle())
                Text(profile?.nickname ?? " ")
                    .font(.title2.bold())
                    .accessibilityIdentifier("profile.nickname")
                if let statusLine {
                    Text(statusLine).font(.subheadline).foregroundStyle(.secondary)
                }
                if let minutes = profile?.recommendedShootMinutes {
                    Label("추천 촬영 \(minutes)분", systemImage: "clock").font(.subheadline)
                }
                if let average = profile?.averageDeliveryMinutes {
                    Label("평균 \(average)분 안 첫 공개", systemImage: "photo.on.rectangle").font(.subheadline)
                }
                if let bio = profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("profile.bio")
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button(action: onChat) {
                    Text("채팅하기").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("profile.chat")
            }
            .padding()
        }
        .navigationTitle(profile?.nickname ?? "작가")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artistUid) {
            do {
                let loaded = try await LaunchArtistProfileService.profile(artistUid: artistUid)
                profile = loaded
                if let path = loaded.photoPath, let data = try? await LaunchArtistProfileService.photoData(path: path) {
                    photo = UIImage(data: data)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
