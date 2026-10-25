import type {TokenMessage} from "firebase-admin/messaging";

/** 사진 문서(`tickets/{ticketId}/photos/{원본 파일명}`)에서 구매 알림이 보는 항목 */
export interface PhotoFields {
  purchasedAt?: unknown;
  fullresUploadedAt?: unknown;
}

/** 이번 변경으로 구매가 새로 기록됐는지. 작가 앱이 고화질본 정보를 더하는 변경이나 찜은 알리지 않는다. */
export function isNewPurchase(before: PhotoFields | undefined, after: PhotoFields | undefined): boolean {
  return before?.purchasedAt == null && after?.purchasedAt != null;
}

/**
 * 작가 기기로 보낼 구매 알림.
 *
 * 알림과 함께 content-available을 보내 백그라운드에 있는 작가 앱을 깨운다. 앱은 깨어나면 서버에서 찜·구매를 다시 읽고
 * 구매한 사진의 고화질본부터 올린다. iOS는 이 깨우기를 미루거나 건너뛸 수 있고, 작가가 앱을 쓸어 올려 종료했으면 깨우지 않는다.
 * 그래서 작가가 보고 앱을 열 수 있게 문구를 함께 보낸다.
 */
export function purchaseMessage(token: string, ticketId: string, fileName: string, hasFullResolution: boolean): TokenMessage {
  return {
    token,
    notification: {
      title: "사진 구매",
      body: hasFullResolution
        ? `${fileName} · 고화질본은 이미 올라가 있습니다.`
        : `${fileName} · 고화질본을 올립니다. 진행되지 않으면 앱을 열어 주세요.`,
    },
    data: {type: "purchase", ticketId, fileName},
    apns: {
      headers: {"apns-push-type": "alert", "apns-priority": "10"},
      payload: {aps: {contentAvailable: true, sound: "default", threadId: ticketId}},
    },
  };
}
