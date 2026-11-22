import Foundation

/// 채팅 보내기 전 연락처·링크 감지(L03). 앱이 보내기를 멈추고 "고치기 / 가리고 보내기"를 고르게 한다.
/// 서버는 막지 않고 표시만 한다(신고·제재 근거). 서버 표시 정규식(웹 `sendLaunchMessage`)이 잡는 것은 모두 잡고,
/// 메신저 아이디 모양("카톡 아이디", "오픈채팅", `@아이디`)을 더 본다. 시험 문장은 Android `:core`와 맞춘다.
public enum ContactFilter {
    public enum Kind: String, Sendable {
        case url
        case email
        case phone
        case messenger
    }

    public struct Match: Sendable, Equatable {
        public let kind: Kind
        public let range: Range<String.Index>
    }

    public struct Result: Sendable, Equatable {
        public let matches: [Match]
        /// 찾은 부분의 글자·숫자를 `*`로 가린 문장(구분 기호는 남긴다)
        public let masked: String
    }

    /// 앞에 있는 것이 먼저 잡힌다(이메일을 `@아이디`로, URL 안의 숫자를 전화번호로 다시 잡지 않는다).
    static let patterns: [(Kind, NSRegularExpression)] = [
        (.email, #"[^\s@]+@[^\s@]+\.[^\s@]+"#),
        (.url, #"(?:https?://|www\.)\S+"#),
        (.url, #"\b[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)*\.(?:com|net|org|kr|io|me|ly|gl|link|app|co|kakao|page)(?:/\S*)?"#),
        (.phone, #"(?:\+?82[-.\s]?|0)1[016789][-.\s]?\d{3,4}[-.\s]?\d{4}"#),
        (.phone, #"\b0(?:2|[3-6][1-5]|70)[-.\s]?\d{3,4}[-.\s]?\d{4}\b"#),
        (.messenger, #"(?:카카오톡|카톡|오픈\s?채팅|오픈\s?카톡|오카|텔레그램|텔레|라인|인스타(?:그램)?|kakao(?:talk)?|telegram|insta(?:gram)?|line)\s*(?:아이디|id|ID|디엠|dm|DM)?\s*[:：]?\s*[A-Za-z0-9_.-]{2,30}"#),
        (.messenger, #"(?:오픈\s?채팅|오픈\s?카톡|카톡\s?아이디|카카오톡\s?아이디)"#),
        (.messenger, #"(?<![A-Za-z0-9._%+-])@[A-Za-z0-9_.]{3,30}"#),
    ].map { kind, pattern in
        (kind, try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
    }

    /// 찾은 것이 없으면 nil
    public static func scan(_ text: String) -> Result? {
        var matches: [Match] = []
        let whole = NSRange(text.startIndex..., in: text)
        for (kind, regex) in patterns {
            for found in regex.matches(in: text, range: whole) {
                guard let range = Range(found.range, in: text),
                      !matches.contains(where: { $0.range.overlaps(range) }) else { continue }
                matches.append(Match(kind: kind, range: range))
            }
        }
        guard !matches.isEmpty else { return nil }
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }
        var masked = ""
        var cursor = text.startIndex
        for match in matches {
            masked += text[cursor..<match.range.lowerBound]
            masked += text[match.range].map { $0.isLetter || $0.isNumber ? "*" : String($0) }.joined()
            cursor = match.range.upperBound
        }
        masked += text[cursor...]
        return Result(matches: matches, masked: masked)
    }
}
