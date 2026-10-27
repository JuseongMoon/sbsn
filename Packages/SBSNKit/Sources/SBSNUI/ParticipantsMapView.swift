import MapKit
import SBSNCore
import SwiftUI

/// 매칭된 두 사람의 위치를 한 지도에 보여 준다. 작가 앱과 고객 앱이 같이 쓴다.
///
/// 처음에는 두 점이 모두 보이게 자동으로 잡고, 사용자가 지도를 움직인 뒤에는 "둘 다 보기"로 다시 맞춘다.
public struct ParticipantsMapView: View {
    public struct Participant: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let point: GeoPoint
        public let updatedAt: Date?
        public let isMe: Bool

        public init(id: String, label: String, point: GeoPoint, updatedAt: Date?, isMe: Bool) {
            self.id = id
            self.label = label
            self.point = point
            self.updatedAt = updatedAt
            self.isMe = isMe
        }
    }

    let participants: [Participant]
    @State private var position = MapCameraPosition.automatic

    public init(participants: [Participant]) {
        self.participants = participants
    }

    public var body: some View {
        Map(position: $position) {
            ForEach(participants) { participant in
                Annotation(participant.label, coordinate: participant.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: participant.isMe ? "person.circle.fill" : "camera.circle.fill")
                            .font(.title)
                            .foregroundStyle(participant.isMe ? Color.blue : Color.orange)
                            .background(Circle().fill(.white).padding(2))
                        if let updatedAt = participant.updatedAt {
                            Text(updatedAt, style: .relative)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button("둘 다 보기", systemImage: "arrow.up.left.and.arrow.down.right") {
                position = .automatic
            }
            .labelStyle(.iconOnly)
            .padding(8)
            .background(.thinMaterial, in: Circle())
            .padding(8)
        }
        .onChange(of: participants.map(\.id)) { _, _ in
            position = .automatic
        }
    }
}

extension ParticipantsMapView.Participant {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}

public extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
