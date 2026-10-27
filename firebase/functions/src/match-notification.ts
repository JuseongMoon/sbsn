import type {TokenMessage} from "firebase-admin/messaging";
import {photographerMessage} from "./notifications.js";

/** 티켓 문서(`tickets/{ticketId}`)에서 매칭 알림이 보는 항목 */
export interface TicketFields {
  customerUid?: unknown;
  photographerUid?: unknown;
}

/** 고객이 만든 매칭 티켓인지. 관리자 스크립트가 작가 시험용으로 만든 티켓(고객 없음)은 알리지 않는다. */
export function isCustomerMatch(ticket: TicketFields | undefined): ticket is TicketFields & {customerUid: string; photographerUid: string} {
  return typeof ticket?.customerUid === "string" && typeof ticket?.photographerUid === "string";
}

/** 매칭 알림이 유효한 시간. 그 뒤에 도착하면 이미 지난 요청이라 보여 주지 않는다. */
export const matchExpiration = 10 * 60 * 1000;

/**
 * 고객이 지도에서 작가를 확정했을 때 작가 기기로 보내는 알림.
 *
 * 배너와 함께 content-available을 보내 백그라운드 작가 앱을 깨운다. 깨어난 앱은 티켓에 "받음"(photographerAckAt)을 남기고
 * presence 리스너를 붙인다. 작가가 앱을 쓸어 올려 종료했으면 iOS가 깨우지 않으므로 배너를 탭해 열어야 한다.
 */
export function matchMessage(token: string, ticketId: string, now: Date): TokenMessage {
  return photographerMessage({
    token,
    title: "새 촬영 요청",
    body: "고객이 촬영을 요청했습니다. 앱을 열어 위치와 채팅을 확인하세요.",
    data: {type: "match", ticketId},
    collapseId: ticketId,
    threadId: ticketId,
    wakesApp: true,
    expiresAt: new Date(now.getTime() + matchExpiration),
  });
}
