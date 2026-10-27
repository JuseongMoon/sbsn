import Foundation
import Testing
@testable import SBSNCore

struct TicketRecordTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func ticket(customerStarted: Bool = false, photographerStarted: Bool = false, ended: Bool = false, cancelled: Bool = false) -> TicketRecord {
        TicketRecord(id: "T1", customerUid: "C", photographerUid: "P", photographerDisplayName: "작가", createdAt: t0,
                     customerStartedAt: customerStarted ? t0.addingTimeInterval(60) : nil,
                     photographerStartedAt: photographerStarted ? t0.addingTimeInterval(90) : nil,
                     endedAt: ended ? t0.addingTimeInterval(600) : nil,
                     cancelledAt: cancelled ? t0.addingTimeInterval(120) : nil,
                     cancelledBy: cancelled ? "C" : nil)
    }

    @Test func phaseIsDerivedFromTimestamps() {
        #expect(ticket().phase == .matched)
        #expect(ticket(customerStarted: true).phase == .waitingForPhotographer)
        #expect(ticket(photographerStarted: true).phase == .waitingForCustomer)
        #expect(ticket(customerStarted: true, photographerStarted: true).phase == .shooting)
        #expect(ticket(customerStarted: true, photographerStarted: true, ended: true).phase == .ended)
    }

    @Test func cancelledWinsOverEverything() {
        #expect(ticket(customerStarted: true, photographerStarted: true, ended: true, cancelled: true).phase == .cancelled)
        #expect(ticket(cancelled: true).phase.isActive == false)
        #expect(ticket(ended: true).phase.isActive == false)
        #expect(ticket(customerStarted: true).phase.isActive == true)
    }

    @Test func eachSideStartsOnlyOnce() {
        let matched = ticket()
        #expect(matched.canStart(.customer))
        #expect(matched.canStart(.photographer))
        let customerStarted = ticket(customerStarted: true)
        #expect(customerStarted.canStart(.customer) == false)
        #expect(customerStarted.canStart(.photographer))
        #expect(ticket(cancelled: true).canStart(.photographer) == false)
        #expect(ticket(customerStarted: true, photographerStarted: true, ended: true).canStart(.customer) == false)
    }

    @Test func anyoneCanCancelUntilBothStarted() {
        // 한쪽만 시작한 뒤 상대가 사라져도 빠져나갈 수 있어야 한다.
        #expect(ticket().canCancel)
        #expect(ticket(customerStarted: true).canCancel)
        #expect(ticket(photographerStarted: true).canCancel)
        #expect(ticket(customerStarted: true, photographerStarted: true).canCancel == false)
        #expect(ticket(cancelled: true).canCancel == false)
        #expect(ticket(customerStarted: true, photographerStarted: true, ended: true).canCancel == false)
    }

    @Test func photographerEndsShootingAndCustomerOnlyAfterGracePeriod() {
        let shooting = ticket(customerStarted: true, photographerStarted: true)
        let photographerStartedAt = shooting.photographerStartedAt!
        #expect(shooting.canEnd(.photographer, at: photographerStartedAt.addingTimeInterval(1)))
        #expect(shooting.canEnd(.customer, at: photographerStartedAt.addingTimeInterval(1)) == false)
        #expect(shooting.canEnd(.customer, at: photographerStartedAt.addingTimeInterval(TicketRecord.customerEndGracePeriod + 1)))
        #expect(ticket(customerStarted: true).canEnd(.photographer, at: t0.addingTimeInterval(99_999)) == false)
        #expect(ticket(customerStarted: true, photographerStarted: true, ended: true).canEnd(.photographer) == false)
    }

    @Test func rolesAreResolvedByUid() {
        let record = ticket()
        #expect(record.role(of: "C") == .customer)
        #expect(record.role(of: "P") == .photographer)
        #expect(record.role(of: "X") == nil)
        #expect(record.uid(of: .photographer) == "P")
    }
}
