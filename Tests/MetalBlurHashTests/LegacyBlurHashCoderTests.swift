import XCTest
import MetalBlurHash

final class LegacyBlurHashCoderTests: XCTestCase {
    static let testImage: String = "image1.jpg"
//    static let testImage: String = "image2.png"
    
    func test_encode() {
        guard let image = UIImage(named: Self.testImage, in: Bundle.module, compatibleWith: nil) else {
            XCTFail("Failed to load image1.jpg from the test bundle")
            return
        }
        
        var blurHash: String?
        measure {
            guard let encodedBlurHash: String = LegacyBlurHashCoder.encode(image, numberOfComponents: (9, 9)) else {
                XCTFail("Failed to encode blur hash")
                return
            }
            blurHash = encodedBlurHash
        }
        
        print(blurHash ?? "")
    }
    
    func test_decode() {
        let blurHash = "|lM~Oi00%#Mwo}wbtRjFoeS|WDWEIoa$s.WBa#niR*X8R*bHbIawt7aeWVRjofs.R*R+axR+WBofs:ofjsofbFWBflfjogs:jsWCfQjZWCbHkCWVWVjbjtjsjsa|ayj@j[oLj[a|j?j[jZoLayWVWBayj[jtf6azWCafoL"
        
        var blurImage: UIImage!
        
        measure {
            guard let decodedImage = LegacyBlurHashCoder.decode(blurHash: blurHash, size: CGSize(width: 3840, height: 2560), punch: 1) else {
                XCTFail("Failed to create image from blur hash")
                return
            }
            blurImage = UIImage(cgImage: decodedImage)
        }
        
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("legacyDecodedImage.jpg")
        
        guard let imageData = blurImage.jpegData(compressionQuality: 1.0) else {
            XCTFail("Failed to generate JPEG data from the image")
            return
        }
        
        do {
            try imageData.write(to: fileURL)
            print("Saved decoded image to \(fileURL.path)")
        } catch {
            XCTFail("Failed to save image: \(error)")
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "The image file was not found at the expected path")
    }
}
