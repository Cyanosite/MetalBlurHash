//
//  BlurHashCoder.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 02. 22..
//

import UIKit

public enum BlurHashCodingMethod {
    case legacy
    case metal
}

protocol BlurHashCoder {
    static func encode(_ image: UIImage, numberOfComponents components: (Int, Int)) -> String?
    static func decode(blurHash: String, size: CGSize, punch: Float) -> CGImage?
}
