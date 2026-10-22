import Foundation

/// 미리보기를 올린 뒤 남는 큰 파일(고화질본·원본)을 어떤 순서로 올릴지 정한다.
///
/// 장당 구매라 고객이 산 사진이 가장 먼저 넘어가야 하고, 그다음 찜한 사진을 미리 올려 구매 즉시 열리게 한다.
/// LTE 업로드는 10분에 수백 MB밖에 못 올리므로 원본(약 20MB)은 구매한 사진만 올린다.
/// 1. 구매한 사진의 고화질본
/// 2. 찜한 사진의 고화질본
/// 3. 구매한 사진의 원본 (원본을 올려도 되는 망일 때만)
/// 4. 나머지 고화질본 (미리 올리기 시간 안일 때만)
/// 같은 순위에서는 먼저 받은 사진부터 올린다.
public enum DeliveryPlanner {
    public struct Candidate: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case fullResolution
            case original
        }

        public let fileName: String
        public let kind: Kind
        public let receivedAt: Date
        public let isFavorited: Bool
        public let isPurchased: Bool

        public init(fileName: String, kind: Kind, receivedAt: Date, isFavorited: Bool, isPurchased: Bool) {
            self.fileName = fileName
            self.kind = kind
            self.receivedAt = receivedAt
            self.isFavorited = isFavorited
            self.isPurchased = isPurchased
        }
    }

    public struct Conditions: Sendable, Equatable {
        /// 찜·구매하지 않은 사진의 고화질본도 미리 올릴지
        public var isPrefetchOpen: Bool
        /// 구매한 사진의 원본을 지금 올려도 되는지(보통 와이파이일 때)
        public var allowsOriginals: Bool

        public init(isPrefetchOpen: Bool, allowsOriginals: Bool) {
            self.isPrefetchOpen = isPrefetchOpen
            self.allowsOriginals = allowsOriginals
        }
    }

    /// 작을수록 먼저 올린다. 지금 올리지 않을 파일이면 nil.
    public static func rank(of candidate: Candidate, under conditions: Conditions) -> Int? {
        switch candidate.kind {
        case .fullResolution where candidate.isPurchased: 0
        case .fullResolution where candidate.isFavorited: 1
        case .original where candidate.isPurchased && conditions.allowsOriginals: 2
        case .fullResolution where conditions.isPrefetchOpen: 3
        default: nil
        }
    }

    /// 다음에 올릴 파일. 올릴 것이 없으면 nil.
    public static func next(from candidates: [Candidate], under conditions: Conditions) -> Candidate? {
        candidates
            .compactMap { candidate in rank(of: candidate, under: conditions).map { (rank: $0, candidate: candidate) } }
            .min { ($0.rank, $0.candidate.receivedAt) < ($1.rank, $1.candidate.receivedAt) }?
            .candidate
    }
}
