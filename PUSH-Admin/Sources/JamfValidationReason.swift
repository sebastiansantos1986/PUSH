// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

/// Only bounded validation messages from non-auth 400/409/422 responses.
/// Raw response bodies are never persisted, rendered as HTML or logged.
enum JamfValidationReason {
    static func sanitized(_ source:String,secrets:[String]=[])->String {
        var text=source
        for (entity,value) in [("&quot;","\""),("&#34;","\""),("&#39;","'"),("&apos;","'"),("&lt;","<"),("&gt;",">"),("&amp;","&")] {text=text.replacingOccurrences(of:entity,with:value)}
        for secret in secrets where !secret.isEmpty {
            text=text.replacingOccurrences(of:secret,with:"[omitted]")
            if let encoded=secret.addingPercentEncoding(withAllowedCharacters:.alphanumerics){text=text.replacingOccurrences(of:encoded,with:"[omitted]")}
        }
        text=text.replacingOccurrences(of:#"(?i)\bbearer\s+[A-Za-z0-9._~+/-]+=*"#,with:"Bearer [omitted]",options:.regularExpression)
        text=text.replacingOccurrences(of:#"(?i)(client[_-]?secret|password|access[_-]?token|refresh[_-]?token|authorization)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;<>]+)"#,with:"$1=[omitted]",options:.regularExpression)
        text=text.replacingOccurrences(of:#"https?://[^\s]+"#,with:"[URL omitted]",options:.regularExpression)
        text=text.replacingOccurrences(of:#"\b[A-Za-z0-9_+/=-]{48,}\b"#,with:"[opaque value omitted]",options:.regularExpression)
        text=String(String.UnicodeScalarView(text.unicodeScalars.filter{!CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)}))
        text=text.replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
        return String(text.prefix(600))
    }
    static func summary(_ data:Data,status:Int,secrets:[String])->String? {
        guard [400,409,422].contains(status),!data.isEmpty,data.count<=65_536 else{return nil}
        var text=""
        if let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
            if let errors=object["errors"] as? [[String:Any]] {text=errors.compactMap{($0["description"] ?? $0["message"] ?? $0["code"]) as? String}.prefix(3).joined(separator:"; ")}
            if text.isEmpty {text=(object["message"] ?? object["description"] ?? object["error"]) as? String ?? ""}
        }else {
            let raw=String(decoding:data,as:UTF8.self)
            guard !raw.uppercased().contains("<!ENTITY") else{return nil}
            var html=raw.replacingOccurrences(of:#"(?is)<(script|style)\b[^>]*>.*?</\1>"#,with:" ",options:.regularExpression)
            // Jamf Classic often returns a small HTML error page with the field
            // validation message in a paragraph. No HTML renderer is invoked.
            if let regex=try? NSRegularExpression(pattern:#"(?is)<p\b[^>]*>(.*?)</p>"#) {
                let ns=html as NSString
                let parts=regex.matches(in:html,range:NSRange(location:0,length:ns.length)).map{ns.substring(with:$0.range(at:1))}
                if let preferred=parts.first(where:{$0.lowercased().contains("error") || $0.lowercased().contains("message")}) {html=preferred}
                else if !parts.isEmpty {html=parts.prefix(3).joined(separator:" ")}
            }
            text=html.replacingOccurrences(of:#"(?s)<[^>]*>"#,with:" ",options:.regularExpression)
        }
        let result=sanitized(text,secrets:secrets)
        return result.isEmpty ? nil:result
    }
}
