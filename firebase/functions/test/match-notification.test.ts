import assert from "node:assert/strict";
import {test} from "node:test";
import {isCustomerMatch, matchExpiration, matchMessage} from "../src/match-notification.js";

test("고객이 만든 티켓만 매칭으로 본다", () => {
  assert.equal(isCustomerMatch({customerUid: "C", photographerUid: "P"}), true);
  // 관리자 스크립트가 작가 시험용으로 만든 티켓
  assert.equal(isCustomerMatch({photographerUid: "P"}), false);
  assert.equal(isCustomerMatch(undefined), false);
  assert.equal(isCustomerMatch({customerUid: 1, photographerUid: "P"}), false);
});

test("매칭 알림은 작가 앱을 깨우고 10분 뒤에는 버려진다", () => {
  const now = new Date("2026-10-26T12:00:00Z");
  const message = matchMessage("token", "T1", now);
  assert.equal(message.token, "token");
  assert.deepEqual(message.data, {type: "match", ticketId: "T1"});
  assert.equal(message.apns?.payload?.aps.contentAvailable, true);
  assert.equal(message.apns?.payload?.aps.threadId, "T1");
  assert.equal(message.apns?.payload?.aps["interruption-level"], "time-sensitive");
  assert.equal(message.apns?.headers?.["apns-push-type"], "alert");
  assert.equal(message.apns?.headers?.["apns-priority"], "10");
  assert.equal(message.apns?.headers?.["apns-collapse-id"], "T1");
  assert.equal(message.apns?.headers?.["apns-expiration"], String((now.getTime() + matchExpiration) / 1000));
  assert.match(message.notification?.body ?? "", /앱을 열어/);
});
