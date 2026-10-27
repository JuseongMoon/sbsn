import type {TokenMessage} from "firebase-admin/messaging";

/** 작가 기기로 보내는 알림의 공통 모양 */
export interface PhotographerAlert {
  token: string;
  title: string;
  body: string;
  /** 앱이 알림을 분류하는 값. `type`은 작가 앱의 `PhotographerPush`와 맞춘다. */
  data: Record<string, string>;
  /** 같은 값의 알림은 기기에서 하나로 합쳐진다(Eventarc가 같은 이벤트를 두 번 보내도 배너는 하나). */
  collapseId: string;
  /** 알림 스레드(티켓) */
  threadId: string;
  /** 백그라운드 작가 앱을 깨워 일을 시키는 알림인지 */
  wakesApp: boolean;
  /** 이 시각이 지나면 APNs가 전달을 포기한다. 오래된 매칭 알림이 나중에 뜨지 않게 한다. */
  expiresAt?: Date;
}

/**
 * 배너 알림(alert, priority 10). `wakesApp`이면 content-available을 함께 보내 백그라운드 앱을 잠깐 깨운다.
 * 매칭·채팅·구매는 지금 사람이 만나서 처리하는 일이라 집중 모드와 알림 요약을 뚫는 time-sensitive로 보낸다.
 * (작가 앱에 Time Sensitive Notifications 권한이 있어야 하고, 없으면 보통 알림으로 떨어진다.)
 */
export function photographerMessage(alert: PhotographerAlert): TokenMessage {
  const headers: Record<string, string> = {
    "apns-push-type": "alert",
    "apns-priority": "10",
    "apns-collapse-id": alert.collapseId,
  };
  if (alert.expiresAt) {
    headers["apns-expiration"] = String(Math.floor(alert.expiresAt.getTime() / 1000));
  }
  return {
    token: alert.token,
    notification: {title: alert.title, body: alert.body},
    data: alert.data,
    apns: {
      headers,
      payload: {
        aps: {
          contentAvailable: alert.wakesApp,
          sound: "default",
          threadId: alert.threadId,
          "interruption-level": "time-sensitive",
        },
      },
    },
  };
}
