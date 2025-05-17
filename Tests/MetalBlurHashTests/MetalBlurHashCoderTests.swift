//
//  MetalBlurHashCoderTests.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 03. 08..
//

import XCTest
import MetalBlurHash

final class MetalBlurHashCoderTests: XCTestCase {
    private static let performanceTestImage: String = "image1.jpg"
    private static let testImage: String = "image2.png"
    private static let blurHash: String = "|lM~Oi00%#Mwo}wbtRjFoeS|WDWEIoa$s.WBa#niR*X8R*bHbIawt7aeWVRjofs.R*R+axR+WBofs:ofjsofbFWBflfjogs:jsWCfQjZWCbHkCWVWVjbjtjsjsa|ayj@j[oLj[a|j?j[jZoLayWVWBayj[jtf6azWCafoL"
    
    func test_encode() {
        guard let image = UIImage(named: Self.testImage, in: Bundle.module, compatibleWith: nil) else {
            XCTFail("Failed to load \(Self.testImage) from the test bundle")
            return
        }
        
        guard let metalBlurHash: String = image.blurHash(numberOfComponents: (9, 9)) else {
            XCTFail("Failed to encode metal blur hash")
            return
        }
        
        guard
            let metalCGImage: CGImage = LegacyBlurHashCoder.decode(blurHash: metalBlurHash, size: CGSize(width: 100, height: 100), punch: 1),
            let legacyCGImage: CGImage = LegacyBlurHashCoder.decode(blurHash: Self.blurHash, size: CGSize(width: 100, height: 100), punch: 1)
        else {
            XCTFail("Decode failed")
            return
        }
        let metalImage: UIImage = UIImage(cgImage: metalCGImage)
        let legacyImage: UIImage = UIImage(cgImage: legacyCGImage)
        
        let (success, rate): (Bool, Double) = ImageComparatorFactory.createComparator(for: .perPixel(perPixelTolerance: 0.05, overallTolerance: 0.02)).compareImages(metalImage, legacyImage)
        
        print("Metal Encode test bad pixel rate: \(rate)")
        if !success {
            XCTFail("Image comparison failed")
        }
    }
    
    func test_encode_performance() {
        guard let image = UIImage(named: Self.performanceTestImage, in: Bundle.module, compatibleWith: nil) else {
            XCTFail("Failed to load \(Self.performanceTestImage) from the test bundle")
            return
        }
        
        measure {
            guard let _: String = image.blurHash(numberOfComponents: (9, 9)) else {
                XCTFail("Failed to encode blur hash")
                return
            }
        }
    }
    
    func test_decode() {
        guard let metalBlurImage = UIImage(blurHash: Self.blurHash, size: CGSize(width: 75, height: 50)) else {
            XCTFail("Failed to create image from blur hash (method: simd)")
            return
        }
        
        guard let legacyBlurCGImage: CGImage = LegacyBlurHashCoder.decode(blurHash: Self.blurHash, size: CGSize(width: 75, height: 50), punch: 1) else {
            XCTFail("Failed to create image from blur hash (method: legacy)")
            return
        }
        
        let (success, _) = ImageComparatorFactory.createComparator(for: .strict).compareImages(metalBlurImage, UIImage(cgImage: legacyBlurCGImage))
        XCTAssertTrue(success)
    }
    
    func test_decode_performance() {
        var blurImage: UIImage!
        
        measure {
            guard let decodedImage = UIImage(blurHash: Self.blurHash, size: CGSize(width: 3840, height: 2560)) else {
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
