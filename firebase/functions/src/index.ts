import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getMessaging, type TokenMessage} from "firebase-admin/messaging";
import {logger, setGlobalOptions} from "firebase-functions";
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/firestore";
import {isCustomerMatch, matchMessage} from "./match-notification.js";
import {isCustomerMessage, messageMessage} from "./message-notification.js";
import {isNewPurchase, purchaseMessage} from "./purchase-notification.js";

initializeApp();
// Firestore (default) 데이터베이스가 서울(asia-northeast3)에 있어 트리거도 같은 리전에 둔다.
setGlobalOptions({region: "asia-northeast3", maxInstances: 5});
// 기본 Compute 계정은 조직 정책으로 권한이 비어 있다. 알림 함수들만 쓰는 계정에 Firestore 읽기·FCM 발송·트리거 수신 권한만 준다.
const serviceAccount = "purchase-notifier@";

/** 작가 기기 토큰. 작가 앱은 익명 로그인이라 작가 uid 하나가 앱 설치(기기) 하나다. */
async function photographerToken(photographerUid: string, context: Record<string, unknown>): Promise<string | undefined> {
  const token = (await getFirestore().doc(`photographers/${photographerUid}`).get()).get("fcmToken");
  if (typeof token !== "string") {
    logger.warn("작가 기기 토큰이 없어 알리지 않음", {...context, photographerUid});
    return undefined;
  }
  return token;
}

// 이벤트는 한 번 이상 전달될 수 있어 같은 알림이 두 번 갈 수 있다. 알림마다 collapse-id를 두어 배너는 하나로 합쳐지고,
// 작가 앱은 같은 티켓·사진을 두 번 처리해도 결과가 같다.
async function send(message: TokenMessage, label: string, context: Record<string, unknown>): Promise<void> {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    logger.info(`에뮬레이터라 보내지 않음: ${label}`, {...context, notification: message.notification, data: message.data});
    return;
  }
  const messageId = await getMessaging().send(message);
  logger.info(`${label} 보냄`, {...context, messageId});
}

/**
 * 고객이 지도에서 작가를 확정해 티켓이 생기면 작가 기기를 깨워 알린다.
 * 작가는 돌아다니며 대기하므로 앱이 백그라운드일 가능성이 높다. 깨어난 앱은 티켓에 "받음"을 남기고 매칭 화면을 준비한다.
 */
export const notifyPhotographerOfMatch = onDocumentCreated({
  document: "tickets/{ticketId}",
  serviceAccount,
}, async (event) => {
  const {ticketId} = event.params;
  const ticket = event.data?.data();
  if (!isCustomerMatch(ticket)) {
    logger.info("고객이 만든 매칭이 아니라 알리지 않음", {ticketId});
    return;
  }
  const token = await photographerToken(ticket.photographerUid, {ticketId});
  if (token) {
    await send(matchMessage(token, ticketId, new Date()), "매칭 알림", {ticketId});
  }
});

/** 고객이 채팅을 보내면 작가 기기에 배너를 띄운다. 매칭 알림 뒤 작가가 앱을 내려도 만남 약속이 이어지게 한다. */
export const notifyPhotographerOfMessage = onDocumentCreated({
  document: "tickets/{ticketId}/messages/{messageId}",
  serviceAccount,
}, async (event) => {
  const {ticketId, messageId} = event.params;
  const message = event.data?.data();
  const ticket = (await getFirestore().doc(`tickets/${ticketId}`).get()).data();
  // 보낸 사람이 고객인지는 규칙이 아니라 티켓 문서로 다시 확인한다. 작가 자신의 글은 알리지 않는다.
  if (!isCustomerMessage(message, ticket?.customerUid) || typeof ticket?.photographerUid !== "string") {
    return;
  }
  const token = await photographerToken(ticket.photographerUid, {ticketId, messageId});
  if (token) {
    await send(messageMessage(token, ticketId, message.text), "채팅 알림", {ticketId, messageId});
  }
});

/**
 * 고객 구매(purchasedAt)가 사진 문서에 새로 기록되면 그 티켓의 작가 기기로 알림을 보낸다.
 * 원본은 작가 폰에만 있어서, 작가 앱이 백그라운드에 있어도 구매한 사진의 고화질본을 올리게 하려는 것이다.
 */
export const notifyPhotographerOfPurchase = onDocumentUpdated({
  document: "tickets/{ticketId}/photos/{photoId}",
  serviceAccount,
}, async (event) => {
  const {ticketId, photoId} = event.params;
  const after = event.data?.after.data();
  if (!isNewPurchase(event.data?.before.data(), after)) {
    return;
  }
  const photographerUid = (await getFirestore().doc(`tickets/${ticketId}`).get()).get("photographerUid");
  if (typeof photographerUid !== "string") {
    logger.warn("티켓에 작가가 없어 알리지 않음", {ticketId, photoId});
    return;
  }
  const token = await photographerToken(photographerUid, {ticketId, photoId});
  if (token) {
    await send(purchaseMessage(token, ticketId, photoId, after?.fullresUploadedAt != null), "구매 알림", {ticketId, photoId});
  }
});
