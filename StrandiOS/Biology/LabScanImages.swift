import UIKit
import PDFKit
import Vision
import StrandImport

/// One report page on its way to the scan: the (EXIF-free, downscaled) image, the text lines Apple's
/// on-device OCR found on it, and which of those lines are blanked before upload.
struct LabScanPage: Identifiable {
    let id = UUID()
    let image: UIImage
    let lines: [LabReportRedaction.Line]
    var redacted: Set<Int>
}

/// Fork: the on-device half of the lab-report scan — PDF/photo → page images → OCR → redaction → JPEG.
/// Nothing here touches the network.
enum LabScanImages {

    static let maxPages = 6
    private static let maxSide: CGFloat = 2048

    /// Render up to `maxPages` PDF pages at ~2x, white-backed.
    static func pages(fromPDF url: URL) -> [UIImage] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<min(doc.pageCount, maxPages)).compactMap { index in
            guard let page = doc.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(2, maxSide / max(bounds.width, bounds.height, 1))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            return UIGraphicsImageRenderer(size: size, format: opaqueFormat).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
        }
    }

    /// Redraw a photo upright and at most `maxSide` long — which also drops its EXIF/GPS metadata.
    static func normalized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: size, format: opaqueFormat).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// OCR the page on-device and pre-select the lines that look personal.
    static func page(_ image: UIImage) async -> LabScanPage {
        let lines = await recognizeLines(image)
        let redacted = LabReportRedaction.linesToRedact(lines)
        NSLog("LabScan: OCR %d line(s), %d blanked", lines.count, redacted.count)
        return LabScanPage(image: image, lines: lines, redacted: redacted)
    }

    /// The page with its blanked lines painted black, as JPEG.
    static func redactedJPEG(_ page: LabScanPage) -> Data? {
        let size = page.image.size
        let rendered = UIGraphicsImageRenderer(size: size, format: opaqueFormat).image { ctx in
            page.image.draw(at: .zero)
            UIColor.black.setFill()
            for i in page.redacted where page.lines.indices.contains(i) {
                ctx.fill(rect(page.lines[i], in: size))
            }
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }

    /// A line's box in image points, padded a little so ascenders/descenders are covered too.
    static func rect(_ line: LabReportRedaction.Line, in size: CGSize) -> CGRect {
        CGRect(x: line.x * size.width, y: line.y * size.height,
               width: line.width * size.width, height: line.height * size.height)
            .insetBy(dx: -4, dy: -3)
    }

    private static var opaqueFormat: UIGraphicsImageRendererFormat {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return f
    }

    private static func recognizeLines(_ image: UIImage) async -> [LabReportRedaction.Line] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            } catch {
                NSLog("LabScan: OCR failed - \(error.localizedDescription)")
                return []
            }
            return (request.results ?? []).compactMap { obs -> LabReportRedaction.Line? in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                let b = obs.boundingBox   // normalized, origin bottom-left
                return LabReportRedaction.Line(text: text, x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            }
        }.value
    }
}
