import Foundation

enum AppConfig {
    static var apiBaseURL: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: urlString) else {
            fatalError("API_BASE_URL missing/invalid in Info.plist")
        }
        return url
    }

    static var signUpURL: URL {
        apiBaseURL.appendingPathComponent("sign-up")
    }
}
