import Foundation

/// Sends a piece of feedback to the developers when the painter chooses Send: one POST of the
/// report, the painting with its marks and the bundle that `FeedbackPackage` wrote, as
/// `multipart/form-data`, to the relay (`feedback-relay/`: a Cloudflare Worker that files them
/// in the developers' private repository; the header of its `worker.js` is the contract).
/// `upload` returns once the relay has taken the report and throws on anything else (offline, a
/// timeout, a refusal), so the sheet can offer Try Again and Share Instead.
///
/// Which uploader a launch uses is `FeedbackUploads.current`: Release builds always send for
/// real, and Debug builds (CI, tests) send nothing (`FeedbackUploadStub`).
nonisolated struct FeedbackUploader: Sendable {
    /// What the relay is reached at: the Worker `moonlight-feedback` of
    /// `.github/workflows/feedback-relay.yml`, whose run summary prints the Worker's URL (its
    /// workers.dev subdomain is the Cloudflare account's, `paul-bordjadze`). The one place the
    /// address is written.
    static let endpoint = URL(string: "https://moonlight-feedback.paul-bordjadze.workers.dev/v1/feedback")!

    /// How long the relay may stay silent before the upload counts as failed.
    static let timeout: TimeInterval = 60

    /// Nothing is cached or kept: a report is sent once.
    static let session = URLSession(configuration: .ephemeral)

    /// How the uploader is told apart in the log and the tests: "live", or a stub's name.
    let name: String
    private let send: @Sendable (FeedbackPackage.Files, String) async throws -> Void

    init(name: String, send: @escaping @Sendable (FeedbackPackage.Files, String) async throws -> Void) {
        self.name = name
        self.send = send
    }

    /// Sends `files`; `app` is the app's version and build (`FeedbackCapture.app`).
    func upload(_ files: FeedbackPackage.Files, app: String) async throws {
        try await send(files, app)
    }

    /// The uploader that reaches the relay. `endpoint` and `session` are the tests' to replace.
    static func live(endpoint: URL = FeedbackUploader.endpoint, session: URLSession = FeedbackUploader.session) -> FeedbackUploader {
        FeedbackUploader(name: "live") { files, app in
            try await FeedbackUploader.post(files, app: app, to: endpoint, using: session)
        }
    }

    nonisolated enum UploadError: Error, Equatable {
        /// The relay answered with this status instead of 2xx.
        case refused(Int)
        case notHTTP
    }

    // MARK: The request

    /// One part of the form.
    nonisolated struct Part: Sendable, Equatable {
        var name: String
        var filename: String
        var contentType: String
        var data: Data
    }

    @concurrent
    private static func post(_ files: FeedbackPackage.Files, app: String, to endpoint: URL, using session: URLSession) async throws {
        let boundary = makeBoundary()
        let form = try parts(of: files)
        let payload = body(of: form, boundary: boundary)
        let urlRequest = request(to: endpoint, app: app, boundary: boundary)
        let (_, response) = try await session.upload(for: urlRequest, from: payload)
        try check(response)
    }

    static func makeBoundary() -> String { "moonlight-\(UUID().uuidString)" }

    static func request(to endpoint: URL, app: String, boundary: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(app, forHTTPHeaderField: "X-Moonlight-App")
        return request
    }

    /// The relay's three parts, read from the files `FeedbackPackage` wrote.
    static func parts(of files: FeedbackPackage.Files) throws -> [Part] {
        let report = try Data(contentsOf: files.report)
        let picture = try Data(contentsOf: files.picture, options: .mappedIfSafe)
        let bundle = try Data(contentsOf: files.bundle, options: .mappedIfSafe)
        return [
            Part(name: "report", filename: files.report.lastPathComponent, contentType: "text/markdown; charset=utf-8", data: report),
            Part(name: "picture", filename: files.picture.lastPathComponent, contentType: "image/png", data: picture),
            Part(name: "bundle", filename: files.bundle.lastPathComponent, contentType: "application/zip", data: bundle),
        ]
    }

    /// The body of a `multipart/form-data` request: each part as a file (so its bytes travel as
    /// they are: a form field's line breaks would become CRLF), between `boundary` lines.
    static func body(of parts: [Part], boundary: String) -> Data {
        var body = Data()
        func line(_ text: String) { body.append(Data(text.utf8)) }
        for part in parts {
            line("--\(boundary)\r\n")
            line("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(quoted(part.filename))\"\r\n")
            line("Content-Type: \(part.contentType)\r\n\r\n")
            body.append(part.data)
            line("\r\n")
        }
        line("--\(boundary)--\r\n")
        return body
    }

    /// A file name as a form's header carries it: quotes and line breaks percent-encoded.
    private static func quoted(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UploadError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw UploadError.refused(http.statusCode) }
    }
}

/// The uploader a launch uses.
nonisolated enum FeedbackUploads {
    /// Release builds (TestFlight, SideStore, the App Store) always send. Debug builds, which
    /// CI and every test run, send nothing: `FeedbackUploadStub` answers instead, unless the
    /// launch says `-feedback-upload live`.
    static var current: FeedbackUploader {
        #if DEBUG
        return FeedbackUploadStub.choose(argument: UserDefaults.standard.string(forKey: "feedback-upload"))
        #else
        return .live()
        #endif
    }
}
