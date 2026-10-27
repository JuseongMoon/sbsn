import assert from "node:assert/strict";
import {test} from "node:test";
import {isNewPurchase, purchaseMessage} from "../src/purchase-notification.js";

test("구매가 처음 기록될 때만 알린다", () => {
  assert.equal(isNewPurchase({}, {purchasedAt: 1}), true);
  assert.equal(isNewPurchase(undefined, {purchasedAt: 1}), true);
  // 작가 앱이 구매한 사진에 고화질본 정보를 더할 때
  assert.equal(isNewPurchase({purchasedAt: 1}, {purchasedAt: 1, fullresUploadedAt: 2}), false);
  // 찜만 했을 때
  assert.equal(isNewPurchase({}, {favoritedAt: 1} as object), false);
  // 구매 기록을 지웠을 때
  assert.equal(isNewPurchase({purchasedAt: 1}, {}), false);
});

test("백그라운드 작가 앱을 깨우는 알림을 만든다", () => {
  const message = purchaseMessage("token", "POC-1", "DSC00001.JPG", false);
  assert.equal(message.token, "token");
  assert.deepEqual(message.data, {type: "purchase", ticketId: "POC-1", fileName: "DSC00001.JPG"});
  assert.equal(message.apns?.payload?.aps.contentAvailable, true);
  assert.equal(message.apns?.payload?.aps.threadId, "POC-1");
  assert.equal(message.apns?.headers?.["apns-push-type"], "alert");
  assert.equal(message.apns?.headers?.["apns-priority"], "10");
  // 같은 구매의 알림이 두 번 와도 배너는 하나
  assert.equal(message.apns?.headers?.["apns-collapse-id"], "POC-1:DSC00001.JPG");
  assert.equal(message.apns?.payload?.aps["interruption-level"], "time-sensitive");
  assert.match(message.notification?.body ?? "", /앱을 열어/);
});

test("고화질본이 이미 올라가 있으면 그렇게 알린다", () => {
  const message = purchaseMessage("token", "POC-1", "DSC00001.JPG", true);
  assert.match(message.notification?.body ?? "", /이미 올라가/);
});
