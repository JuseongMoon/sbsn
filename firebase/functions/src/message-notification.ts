import type {TokenMessage} from "firebase-admin/messaging";
import {photographerMessage} from "./notifications.js";

/** 채팅 문서(`tickets/{ticketId}/messages/{messageId}`)에서 알림이 보는 항목 */
export interface MessageFields {
  senderUid?: unknown;
  text?: unknown;
}

/** 고객이 보낸 메시지인지. 작가 자신의 메시지는 알리지 않는다. 보낸 사람은 규칙이 아니라 티켓 문서로 다시 확인한다. */
export function isCustomerMessage(message: MessageFields | undefined, customerUid: unknown): message is MessageFields & {senderUid: string; text: string} {
  return typeof customerUid === "string" && message?.senderUid === customerUid && typeof message?.text === "string";
}

/** 배너에 보여 줄 길이로 자른다. */
export function previewText(text: string, limit = 100): string {
  const trimmed = text.trim();
  return trimmed.length <= limit ? trimmed : trimmed.slice(0, limit - 1) + "…";
}

/** 고객 메시지를 작가 기기로 보내는 알림. 매칭 알림 뒤 작가가 앱을 내려도 만남 약속이 이어지게 한다. */
export function messageMessage(token: string, ticketId: string, text: string): TokenMessage {
  return photographerMessage({
    token,
    title: "고객 메시지",
    body: previewText(text),
    data: {type: "message", ticketId},
    collapseId: `${ticketId}:message`,
    threadId: ticketId,
    wakesApp: false,
  });
}
