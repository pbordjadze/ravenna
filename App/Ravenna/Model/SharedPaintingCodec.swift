import Foundation
import PaintCore
import UniformTypeIdentifiers

extension UTType {
    /// A mosaic sent to someone else to set (`SharedPainting`), a `.ravenna` file: the type
    /// `Config/Info.plist` exports and opens. Paint by Moonlight's `.moonlight` is its own, so the
    /// two apps never claim each other's files.
    nonisolated static let moonlightPainting = UTType(exportedAs: "com.pbordjadze.ravenna.mosaic")
}

/// The app's side of `SharedPainting`: the template compressed with LZFSE, and how an opened file
/// is told from a photo.
nonisolated enum SharedPaintingCodec {
    static let fileExtension = "ravenna"

    /// Whether `data` is a shared painting rather than a photo, by its first bytes ("PBMS"),
    /// whatever the file was called on the way.
    static func isSharedPainting(_ data: Data) -> Bool {
        data.prefix(4).elementsEqual("PBMS".utf8)
    }

    /// The file's bytes, the template compressed with LZFSE.
    static func encode(_ shared: SharedPainting) throws -> Data {
        try shared.encoded(compression: .lzfse) { try ($0 as NSData).compressed(using: .lzfse) as Data }
    }

    /// Reads a file someone sent, as hostile input: the template's length is bounded by what the
    /// library stores before anything decompresses, and the decoders check the rest.
    static func decode(_ data: Data) throws -> SharedPainting {
        try SharedPainting(encoded: data, maximumTemplateBytes: ArtworkStore.maximumTemplateBytes) { method, stream, length in
            guard method == .lzfse else { throw Template.CodingError.corrupt("compression") }
            return try ArtworkStore.lzfseDecoded(stream, maximumBytes: length)
        }
    }
}
