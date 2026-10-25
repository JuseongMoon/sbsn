import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {logger, setGlobalOptions} from "firebase-functions";
import {onDocumentUpdated} from "firebase-functions/firestore";
import {isNewPurchase, purchaseMessage} from "./purchase-notification.js";

initializeApp();
// Firestore (default) 데이터베이스가 서울(asia-northeast3)에 있어 트리거도 같은 리전에 둔다.
setGlobalOptions({region: "asia-northeast3", maxInstances: 5});

/**
 * 고객 구매(purchasedAt)가 사진 문서에 새로 기록되면 그 티켓을 만든 작가 기기로 알림을 보낸다.
 * 원본은 작가 폰에만 있어서, 작가 앱이 백그라운드에 있어도 구매한 사진의 고화질본을 올리게 하려는 것이다.
 */
export const notifyPhotographerOfPurchase = onDocumentUpdated({
  document: "tickets/{ticketId}/photos/{photoId}",
  // 기본 Compute 계정은 조직 정책으로 권한이 비어 있다. 이 함수만 쓰는 계정에 Firestore 읽기·FCM 발송·트리거 수신 권한만 준다.
  serviceAccount: "purchase-notifier@",
}, async (event) => {
  const {ticketId, photoId} = event.params;
  const after = event.data?.after.data();
  if (!isNewPurchase(event.data?.before.data(), after)) {
    return;
  }

  const db = getFirestore();
  const photographerUid = (await db.doc(`tickets/${ticketId}`).get()).get("photographerUid");
  if (typeof photographerUid !== "string") {
    logger.warn("티켓에 작가가 없어 알리지 않음", {ticketId, photoId});
    return;
  }
  // 작가 앱은 익명 로그인이라 작가 uid 하나가 앱 설치(기기) 하나다.
  // 정식 작가 계정을 만들면 티켓을 만든 기기를 따로 기록해 원본이 있는 그 기기로만 보낸다.
  const token = (await db.doc(`photographers/${photographerUid}`).get()).get("fcmToken");
  if (typeof token !== "string") {
    logger.warn("작가 기기 토큰이 없어 알리지 않음", {ticketId, photoId, photographerUid});
    return;
  }

  const message = purchaseMessage(token, ticketId, photoId, after?.fullresUploadedAt != null);
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    logger.info("에뮬레이터라 보내지 않음", {ticketId, photoId, notification: message.notification, data: message.data});
    return;
  }
  // 이벤트는 한 번 이상 전달될 수 있어 같은 알림이 두 번 갈 수 있다. 작가 앱은 이미 올린 사진을 다시 올리지 않는다.
  const messageId = await getMessaging().send(message);
  logger.info("구매 알림 보냄", {ticketId, photoId, messageId});
});
