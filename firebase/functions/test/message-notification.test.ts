import assert from "node:assert/strict";
import {test} from "node:test";
import {isCustomerMessage, messageMessage, previewText} from "../src/message-notification.js";

test("고객이 보낸 글만 작가에게 알린다", () => {
  assert.equal(isCustomerMessage({senderUid: "C", text: "경복궁 정문이요"}, "C"), true);
  // 작가 자신의 메시지
  assert.equal(isCustomerMessage({senderUid: "P", text: "네"}, "C"), false);
  // 고객이 없는 티켓, 글이 아닌 값
  assert.equal(isCustomerMessage({senderUid: "C", text: "안녕"}, undefined), false);
  assert.equal(isCustomerMessage({senderUid: "C", text: 3}, "C"), false);
});

test("배너 문구는 100자로 자른다", () => {
  assert.equal(previewText("  안녕하세요  "), "안녕하세요");
  const long = "가".repeat(150);
  assert.equal(previewText(long).length, 100);
  assert.ok(previewText(long).endsWith("…"));
});

test("채팅 알림은 배너만 보내고 같은 티켓의 글은 하나로 합친다", () => {
  const message = messageMessage("token", "T1", "정문 앞에 있어요");
  assert.deepEqual(message.data, {type: "message", ticketId: "T1"});
  assert.equal(message.notification?.body, "정문 앞에 있어요");
  assert.equal(message.apns?.payload?.aps.contentAvailable, false);
  assert.equal(message.apns?.headers?.["apns-collapse-id"], "T1:message");
  assert.equal(message.apns?.headers?.["apns-expiration"], undefined);
});
