//
//  SIMDBlurHashCoderTests.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 02. 22..
//

import XCTest
import MetalBlurHash

final class SIMDBlurHashCoderTests: XCTestCase {
    static let testImage: String = "image1.jpg"
//    static let testImage: String = "image2.png"
    
    func test_encode() {
        guard let image = UIImage(named: Self.testImage, in: Bundle.module, compatibleWith: nil) else {
            XCTFail("Failed to load image1.jpg from the test bundle")
            return
        }
        
        guard let simdBlurHash: String = image.blurHash(numberOfComponents: (9, 9), method: .simd) else {
            XCTFail("Failed to encode blur hash (method: simd)")
            return
        }
        
        guard let legacyBlurHash: String = image.blurHash(numberOfComponents: (9, 9), method: .legacy) else {
            XCTFail("Failed to encode legacy blur hash (method: legacy)")
            return
        }
        
        guard let simdImage: UIImage = UIImage(blurHash: simdBlurHash, size: CGSize(width: 500, height: 500), method: .simd),
              let legacyImage: UIImage = UIImage(blurHash: legacyBlurHash, size: CGSize(width: 500, height: 500), method: .simd)
        else {
            XCTFail("Decode failed")
            return
        }
        
        let (success, rate): (Bool, Double) = ImageComparatorFactory.createComparator(for: .perPixel(perPixelTolerance: 0.02, overallTolerance: 0.01)).compareImages(simdImage, legacyImage)
        
        print("bad pixel rate: \(rate)")
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
            guard let _: String = image.blurHash(numberOfComponents: (9, 9), method: .simd) else {
                XCTFail("Failed to encode blur hash")
                return
            }
        }
    }
    
    func test_decode() {
        let blurHash = "|lM~Oi00%#Mwo}wbtRjFoeS|WDWEIoa$s.WBa#niR*X8R*bHbIawt7aeWVRjofs.R*R+axR+WBofs:ofjsofbFWBflfjogs:jsWCfQjZWCbHkCWVWVjbjtjsjsa|ayj@j[oLj[a|j?j[jZoLayWVWBayj[jtf6azWCafoL"
        
        guard let simdBlurImage = UIImage(blurHash: blurHash, size: CGSize(width: 75, height: 50), method: .simd) else {
            XCTFail("Failed to create image from blur hash (method: simd)")
            return
        }
        
        guard let legacyBlurImage = UIImage(blurHash: blurHash, size: CGSize(width: 75, height: 50), method: .legacy) else {
            XCTFail("Failed to create image from blur hash (method: legacy)")
            return
        }
        
        XCTAssertEqual(simdBlurImage.pngData(), legacyBlurImage.pngData())
    }
    
    func test_decode_performance() {
        let blurHash = "|lM~Oi00%#Mwo}wbtRjFoeS|WDWEIoa$s.WBa#niR*X8R*bHbIawt7aeWVRjofs.R*R+axR+WBofs:ofjsofbFWBflfjogs:jsWCfQjZWCbHkCWVWVjbjtjsjsa|ayj@j[oLj[a|j?j[jZoLayWVWBayj[jtf6azWCafoL"
                
        measure {
            guard let _ = UIImage(blurHash: blurHash, size: CGSize(width: 3840, height: 2560), method: .simd) else {
                XCTFail("Failed to create image from blur hash")
                return
            }
        }
    }
}

