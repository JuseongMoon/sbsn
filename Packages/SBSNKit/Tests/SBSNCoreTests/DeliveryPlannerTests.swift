import Foundation
import Testing
@testable import SBSNCore

struct DeliveryPlannerTests {
    typealias Candidate = DeliveryPlanner.Candidate
    let open = DeliveryPlanner.Conditions(isPrefetchOpen: true, allowsOriginals: true)

    func candidate(_ name: String, _ kind: Candidate.Kind = .fullResolution, second: TimeInterval,
                   favorited: Bool = false, purchased: Bool = false) -> Candidate {
        Candidate(fileName: name, kind: kind, receivedAt: Date(timeIntervalSince1970: second), isFavorited: favorited, isPurchased: purchased)
    }

    @Test func purchasedFullResolutionGoesFirstEvenIfReceivedLast() {
        let candidates = [
            candidate("A", second: 1),
            candidate("B", second: 2, favorited: true),
            candidate("C", second: 3, purchased: true),
        ]
        #expect(DeliveryPlanner.next(from: candidates, under: open)?.fileName == "C")
    }

    @Test func favoritedComesBeforePurchasedOriginalAndPrefetch() {
        let candidates = [
            candidate("A", second: 1),
            candidate("B", .original, second: 2, purchased: true),
            candidate("C", second: 3, favorited: true),
        ]
        #expect(DeliveryPlanner.next(from: candidates, under: open)?.fileName == "C")
    }

    @Test func purchasedOriginalComesBeforePrefetch() {
        let candidates = [candidate("A", second: 1), candidate("B", .original, second: 2, purchased: true)]
        #expect(DeliveryPlanner.next(from: candidates, under: open) == candidates[1])
    }

    @Test func sameRankFollowsReceivedOrder() {
        let candidates = [candidate("B", second: 2), candidate("A", second: 1), candidate("C", second: 3)]
        #expect(DeliveryPlanner.next(from: candidates, under: open)?.fileName == "A")
    }

    @Test func neverUploadsOriginalsThatWereNotPurchased() {
        let candidates = [candidate("A", .original, second: 1, favorited: true)]
        #expect(DeliveryPlanner.next(from: candidates, under: open) == nil)
    }

    @Test func holdsPurchasedOriginalsWhenNetworkDoesNotAllowThem() {
        let cellular = DeliveryPlanner.Conditions(isPrefetchOpen: true, allowsOriginals: false)
        let candidates = [candidate("A", .original, second: 1, purchased: true), candidate("B", second: 2)]
        #expect(DeliveryPlanner.next(from: candidates, under: cellular)?.fileName == "B")
    }

    @Test func stopsPrefetchingButKeepsFavoritedAndPurchasedAfterWindowCloses() {
        let closed = DeliveryPlanner.Conditions(isPrefetchOpen: false, allowsOriginals: false)
        #expect(DeliveryPlanner.next(from: [candidate("A", second: 1)], under: closed) == nil)
        #expect(DeliveryPlanner.next(from: [candidate("A", second: 1), candidate("B", second: 2, favorited: true)], under: closed)?.fileName == "B")
        #expect(DeliveryPlanner.next(from: [candidate("A", second: 1, purchased: true)], under: closed)?.fileName == "A")
    }
}
