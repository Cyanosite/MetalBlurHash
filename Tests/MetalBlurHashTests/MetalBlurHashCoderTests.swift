//
//  MetalBlurHashCoderTests.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 03. 08..
//

import XCTest
import MetalBlurHash

final class MetalBlurHashCoderTests: XCTestCase {
    static let testImage: String = "image1.jpg"
//    static let testImage: String = "image2.png"
    
    func test_encode() {
        guard let image = UIImage(named: Self.testImage, in: Bundle.module, compatibleWith: nil) else {
            XCTFail("Failed to load image1.jpg from the test bundle")
            return
        }
        
        guard let metalBlurHash: String = image.blurHash(numberOfComponents: (9, 9), method: .metal) else {
            XCTFail("Failed to encode blur hash (method: simd)")
            return
        }
        
        guard let legacyBlurHash: String = image.blurHash(numberOfComponents: (9, 9), method: .legacy) else {
            XCTFail("Failed to encode legacy blur hash (method: legacy)")
            return
        }
        
        guard let metalImage: UIImage = UIImage(blurHash: metalBlurHash, size: CGSize(width: 100, height: 100), method: .legacy),
              let legacyImage: UIImage = UIImage(blurHash: legacyBlurHash, size: CGSize(width: 100, height: 100), method: .legacy)
        else {
            XCTFail("Decode failed")
            return
        }
        
        let (success, rate): (Bool, Double) = ImageComparatorFactory.createComparator(for: .perPixel(perPixelTolerance: 0.05, overallTolerance: 0.02)).compareImages(metalImage, legacyImage)
        
        print("Metal Encode test bad pixel rate: \(rate)")
        if !success {
            XCTFail("Image comparison failed")
        }
    }
    
    func test_encode_performance() {
        guard let image = UIImage(named: Self.testImage, in: Bundle.module, compatibleWith: nil) else {
            XCTFail("Failed to load image1.jpg from the test bundle")
            return
        }
        
        measure {
            guard let _: String = image.blurHash(numberOfComponents: (9, 9), method: .metal) else {
                XCTFail("Failed to encode blur hash")
                return
            }
        }
    }
    
    func test_decode() {
        let blurHash = "|lM~Oi00%#Mwo}wbtRjFoeS|WDWEIoa$s.WBa#niR*X8R*bHbIawt7aeWVRjofs.R*R+axR+WBofs:ofjsofbFWBflfjogs:jsWCfQjZWCbHkCWVWVjbjtjsjsa|ayj@j[oLj[a|j?j[jZoLayWVWBayj[jtf6azWCafoL"
        
        guard let metalBlurImage = UIImage(blurHash: blurHash, size: CGSize(width: 75, height: 50), method: .metal) else {
            XCTFail("Failed to create image from blur hash (method: simd)")
            return
        }
        
        guard let legacyBlurImage = UIImage(blurHash: blurHash, size: CGSize(width: 75, height: 50), method: .legacy) else {
            XCTFail("Failed to create image from blur hash (method: legacy)")
            return
        }
        
        let (success, _) = ImageComparatorFactory.createComparator(for: .strict).compareImages(metalBlurImage, legacyBlurImage)
        XCTAssertTrue(success)
    }
    
    func test_decode_performance() {
        let blurHash = "|lM~Oi00%#Mwo}wbtRjFoeS|WDWEIoa$s.WBa#niR*X8R*bHbIawt7aeWVRjofs.R*R+axR+WBofs:ofjsofbFWBflfjogs:jsWCfQjZWCbHkCWVWVjbjtjsjsa|ayj@j[oLj[a|j?j[jZoLayWVWBayj[jtf6azWCafoL"
        
        var blurImage: UIImage!
        
        measure {
            guard let decodedImage = UIImage(blurHash: blurHash, size: CGSize(width: 3840, height: 2560), method: .metal) else {
                XCTFail("Failed to create image from blur hash")
                return
            }
            blurImage = decodedImage
        }
        
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("metalDecodedImage.jpg")
        
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
