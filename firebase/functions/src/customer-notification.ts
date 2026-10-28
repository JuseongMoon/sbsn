import type {TokenMessage} from "firebase-admin/messaging";
import {previewText} from "./message-notification.js";
import {deviceAlertMessage} from "./notifications.js";

// 고객 기기로 보내는 알림. 고객 앱이 백그라운드에 있으면 티켓 리스너가 멈춰 작가의 메시지·시작·취소를 모른다.
// 만나러 걸어가는 동안 폰을 넣어 두는 경우를 위해 배너로 알린다. 고객 자신이 한 일은 알리지 않고, 앱을 깨우지도 않는다.
// `data.type`은 고객 앱의 `CustomerPush`와 맞춘다.

/** 티켓 문서에서 고객 알림이 보는 항목 */
export interface TicketFields {
  customerUid?: unknown;
  photographerUid?: unknown;
  photographerDisplayName?: unknown;
  customerStartedAt?: unknown;
  photographerStartedAt?: unknown;
  endedAt?: unknown;
  cancelledAt?: unknown;
  cancelledBy?: unknown;
}

/** 고객에게 알릴 티켓 변화 */
export type TicketChange = "photographerStarted" | "photographerCancelled" | "ended";

/**
 * 이번 변경에서 고객에게 알릴 티켓 변화. 고객이 직접 한 취소는 알리지 않는다.
 * 작가가 시작을 눌렀을 때는 고객이 아직 시작하지 않았을 때만 알린다(이미 눌렀으면 그 자리에서 촬영이 시작된다).
 * 종료는 대개 작가가 하지만, 작가가 사라져 고객이 종료한 경우도 같은 알림이 간다(고객 앱은 앞에 있으면 배너를 띄우지 않는다).
 */
export function customerTicketChange(before: TicketFields | undefined, after: TicketFields | undefined): TicketChange | undefined {
  if (!before || !after || typeof after.customerUid !== "string") {
    return undefined;
  }
  if (before.cancelledAt == null && after.cancelledAt != null) {
    return after.cancelledBy === after.photographerUid ? "photographerCancelled" : undefined;
  }
  if (before.endedAt == null && after.endedAt != null) {
    return "ended";
  }
  if (before.photographerStartedAt == null && after.photographerStartedAt != null && after.customerStartedAt == null) {
    return "photographerStarted";
  }
  return undefined;
}

export function customerTicketMessage(token: string, ticketId: string, change: TicketChange): TokenMessage {
  const content = {
    photographerStarted: {title: "작가가 촬영 시작을 눌렀습니다", body: "작가를 만났다면 앱에서 촬영 시작을 눌러 주세요.", isTimeSensitive: true},
    photographerCancelled: {title: "작가가 촬영을 취소했습니다", body: "지도에서 다른 작가를 찾을 수 있습니다.", isTimeSensitive: true},
    ended: {title: "촬영이 끝났습니다", body: "준비된 사진은 계속 구매할 수 있습니다.", isTimeSensitive: false},
  }[change];
  return deviceAlertMessage({
    token,
    title: content.title,
    body: content.body,
    data: {type: "ticket", ticketId, change},
    collapseId: `${ticketId}:${change}`,
    androidChannelId: "ticket",
    threadId: ticketId,
    wakesApp: false,
    isTimeSensitive: content.isTimeSensitive,
  });
}

/** 작가가 보낸 메시지인지. 보낸 사람은 규칙이 아니라 티켓 문서로 다시 확인한다. */
export function isPhotographerMessage(
  message: {senderUid?: unknown; text?: unknown} | undefined,
  photographerUid: unknown,
): message is {senderUid: string; text: string} {
  return typeof photographerUid === "string" && message?.senderUid === photographerUid && typeof message?.text === "string";
}

export function customerChatMessage(token: string, ticketId: string, photographerName: unknown, text: string): TokenMessage {
  return deviceAlertMessage({
    token,
    title: typeof photographerName === "string" && photographerName.length > 0 ? `${photographerName} 작가` : "작가 메시지",
    body: previewText(text),
    data: {type: "message", ticketId},
    collapseId: `${ticketId}:message`,
    androidChannelId: "message",
    threadId: ticketId,
    wakesApp: false,
  });
}

/** 사진 문서에서 고객 알림이 보는 항목 */
export interface PurchasedPhotoFields {
  purchasedAt?: unknown;
  fullresUploadedAt?: unknown;
  deliveredAt?: unknown;
}

/**
 * 산 사진의 고화질본이 이번 변경으로 올라왔는지. 고화질본이 미리 올라가 있던 사진은 구매 버튼을 누른 고객 앱이
 * 바로 저장하므로 알리지 않는다. 고화질본이 나중에 오는 동안 고객이 앱을 내렸을 때를 위한 알림이다.
 */
export function isPurchasedPhotoReady(before: PurchasedPhotoFields | undefined, after: PurchasedPhotoFields | undefined): boolean {
  return before?.fullresUploadedAt == null && after?.fullresUploadedAt != null && after?.purchasedAt != null && after?.deliveredAt == null;
}

export function photoReadyMessage(token: string, ticketId: string, fileName: string): TokenMessage {
  return deviceAlertMessage({
    token,
    title: "구매한 사진이 준비됐습니다",
    body: `${fileName} · 앱을 열면 사진 앱에 저장됩니다.`,
    data: {type: "photo", ticketId, fileName},
    collapseId: `${ticketId}:${fileName}:ready`,
    androidChannelId: "photo",
    threadId: ticketId,
    wakesApp: false,
    isTimeSensitive: false,
  });
}
