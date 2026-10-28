import assert from "node:assert/strict";
import {test} from "node:test";
import {
  customerChatMessage,
  customerTicketChange,
  customerTicketMessage,
  isPhotographerMessage,
  isPurchasedPhotoReady,
  photoReadyMessage,
} from "../src/customer-notification.js";

const base = {customerUid: "C", photographerUid: "P", photographerDisplayName: "작가"};
const at = new Date("2026-10-28T12:00:00Z");

test("작가가 먼저 시작하면 고객에게 알리고, 고객이 이미 시작했으면 알리지 않는다", () => {
  assert.equal(customerTicketChange(base, {...base, photographerStartedAt: at}), "photographerStarted");
  assert.equal(customerTicketChange({...base, customerStartedAt: at}, {...base, customerStartedAt: at, photographerStartedAt: at}), undefined);
});

test("작가가 취소하면 알리고, 고객 자신의 취소는 알리지 않는다", () => {
  assert.equal(customerTicketChange(base, {...base, cancelledAt: at, cancelledBy: "P"}), "photographerCancelled");
  assert.equal(customerTicketChange(base, {...base, cancelledAt: at, cancelledBy: "C"}), undefined);
});

test("종료는 한 번만 알리고, 받음 표시 같은 다른 변화는 알리지 않는다", () => {
  const shooting = {...base, customerStartedAt: at, photographerStartedAt: at};
  assert.equal(customerTicketChange(shooting, {...shooting, endedAt: at}), "ended");
  assert.equal(customerTicketChange({...shooting, endedAt: at}, {...shooting, endedAt: at}), undefined);
  const acknowledged = {...base, photographerAckAt: at};
  assert.equal(customerTicketChange(base, acknowledged), undefined);
  // 관리자 스크립트의 작가 단독 시험 티켓(고객 없음)
  assert.equal(customerTicketChange({photographerUid: "P"}, {photographerUid: "P", endedAt: at}), undefined);
});

test("티켓 알림은 고객 앱을 깨우지 않고, 종료는 집중 모드를 뚫지 않는다", () => {
  const started = customerTicketMessage("token", "T1", "photographerStarted");
  assert.deepEqual(started.data, {type: "ticket", ticketId: "T1", change: "photographerStarted"});
  assert.equal(started.apns?.payload?.aps.contentAvailable, false);
  assert.equal(started.apns?.payload?.aps["interruption-level"], "time-sensitive");
  assert.equal(started.apns?.headers?.["apns-collapse-id"], "T1:photographerStarted");
  assert.equal(customerTicketMessage("token", "T1", "ended").apns?.payload?.aps["interruption-level"], "active");
});

test("작가 메시지만 고객에게 알리고 제목에 작가 이름을 쓴다", () => {
  assert.equal(isPhotographerMessage({senderUid: "P", text: "정문 앞이에요"}, "P"), true);
  assert.equal(isPhotographerMessage({senderUid: "C", text: "정문 앞이에요"}, "P"), false);
  assert.equal(isPhotographerMessage({senderUid: "P"}, "P"), false);
  const message = customerChatMessage("token", "T1", "아이폰작가", "정문 앞이에요");
  assert.equal(message.notification?.title, "아이폰작가 작가");
  assert.equal(message.notification?.body, "정문 앞이에요");
  assert.deepEqual(message.data, {type: "message", ticketId: "T1"});
  assert.equal(customerChatMessage("token", "T1", undefined, "안녕하세요").notification?.title, "작가 메시지");
});

test("산 사진의 고화질본이 나중에 올라올 때만 알린다", () => {
  assert.equal(isPurchasedPhotoReady({purchasedAt: at}, {purchasedAt: at, fullresUploadedAt: at}), true);
  // 고화질본이 미리 올라가 있던 사진을 산 경우: 고객 앱이 바로 저장한다.
  assert.equal(isPurchasedPhotoReady({fullresUploadedAt: at}, {fullresUploadedAt: at, purchasedAt: at}), false);
  // 사지 않은 사진의 미리 올리기
  assert.equal(isPurchasedPhotoReady({}, {fullresUploadedAt: at}), false);
  // 이미 저장됨
  assert.equal(isPurchasedPhotoReady({purchasedAt: at}, {purchasedAt: at, fullresUploadedAt: at, deliveredAt: at}), false);
  const message = photoReadyMessage("token", "T1", "DSC00001.JPG");
  assert.deepEqual(message.data, {type: "photo", ticketId: "T1", fileName: "DSC00001.JPG"});
  assert.equal(message.apns?.headers?.["apns-collapse-id"], "T1:DSC00001.JPG:ready");
  assert.equal(message.apns?.payload?.aps.contentAvailable, false);
});

test("안드로이드는 알림 종류별 채널과 같은 collapse 값의 tag로 받는다", () => {
  const ticket = customerTicketMessage("token", "T1", "ended");
  assert.deepEqual(ticket.android, {priority: "high", notification: {channelId: "ticket", tag: "T1:ended"}});
  assert.equal(customerChatMessage("token", "T1", "작가", "안녕").android?.notification?.channelId, "message");
  assert.deepEqual(photoReadyMessage("token", "T1", "A.JPG").android?.notification, {channelId: "photo", tag: "T1:A.JPG:ready"});
});
