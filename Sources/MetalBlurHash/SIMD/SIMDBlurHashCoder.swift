//
//  SIMDBlurHashCoder.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 02. 22..
//

import UIKit
import simd

typealias Pixel = SIMD3<Float>

final class SIMDBlurHashCoder: BlurHashCoder {
    // - MARK: - Encoder
    
    static func encode(_ image: UIImage, numberOfComponents components: (Int, Int)) -> String? {
        guard components <= (9, 9) else { return nil }
        
        let pixelWidth: Int = Int(round(image.size.width * image.scale))
        let pixelHeight: Int = Int(round(image.size.height * image.scale))
        
        guard let context: CGContext = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: image.scale, y: -image.scale)
        context.translateBy(x: 0, y: -image.size.height)
        
        UIGraphicsPushContext(context)
        image.draw(at: .zero)
        UIGraphicsPopContext()
        
        guard let cgImage: CGImage = context.makeImage(),
              let dataProvider: CGDataProvider = cgImage.dataProvider,
              let data: CFData = dataProvider.data,
              let pixels: UnsafePointer<UInt8> = CFDataGetBytePtr(data) else {
            assertionFailure("Unexpected error!")
            return nil
        }
        
        let width: Int = cgImage.width
        let height: Int = cgImage.height
        let bytesPerRow: Int = cgImage.bytesPerRow
        
        let bytesPerPixel: Int = cgImage.bitsPerPixel / 8
        var factors: [Pixel] = []
        
        let cosineXLookup: [[Float]] = (0..<components.0).map { frequencyX in
            (0..<width).map { innerX in
                cos(Float.pi * Float(frequencyX) * Float(innerX) / Float(width))
            }
        }

        let cosineYLookup: [[Float]] = (0..<components.1).map { frequencyY in
            (0..<height).map { innerY in
                cos(Float.pi * Float(frequencyY) * Float(innerY) / Float(height))
            }
        }
        
        let scale: Float = 1.0 / Float(width * height)
        
        for frequencyY in 0 ..< components.1 {
            let cosineY = cosineYLookup[frequencyY]
            
            for frequencyX in 0 ..< components.0 {
                let cosineX = cosineXLookup[frequencyX]
                
                let normalisation: Float = (frequencyX == 0 && frequencyY == 0) ? 1 : 2
                let factor: Pixel = {
                    var accumulator = Pixel(0, 0, 0)

                    for innerX in 0 ..< width {
                        for innerY in 0 ..< height {
                            let basis: Float = normalisation * cosineX[innerX] * cosineY[innerY]
                            let pixelOffset = bytesPerPixel * innerX + 0 + innerY * bytesPerRow
                            
                            let rgb = Pixel(
                                sRGBToLinear(pixels[pixelOffset + 0]),
                                sRGBToLinear(pixels[pixelOffset + 1]),
                                sRGBToLinear(pixels[pixelOffset + 2])
                            )
                            
                            accumulator += basis * rgb
                        }
                    }
                    
                    return accumulator * scale
                }()
                factors.append(factor)
            }
        }
        
        let dc = factors.first!
        let ac = factors.dropFirst()
        
        var hash = ""
        
        let sizeFlag = (components.0 - 1) + (components.1 - 1) * 9
        hash += sizeFlag.encode83(length: 1)
        
        let maximumValue: Float
        if ac.count > 0 {
            let actualMaximumValue = ac.map({ max(abs($0.x), abs($0.y), abs($0.z)) }).max()!
            let quantisedMaximumValue = Int(max(0, min(82, floor(actualMaximumValue * 166 - 0.5))))
            maximumValue = Float(quantisedMaximumValue + 1) / 166
            hash += quantisedMaximumValue.encode83(length: 1)
        } else {
            maximumValue = 1
            hash += 0.encode83(length: 1)
        }
        
        hash += encodeDC(dc).encode83(length: 4)
        
        for factor in ac {
            hash += encodeAC(factor, maximumValue: maximumValue).encode83(length: 2)
        }
        
        return hash
    }
    
    // MARK: - Decoder
    
    static func decode(blurHash: String, size: CGSize, punch: Float) -> CGImage? {
        guard blurHash.count >= 6 else { return nil }
        
        let sizeFlag = String(blurHash[0]).decode83()
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        
        let quantisedMaximumValue = String(blurHash[1]).decode83()
        let maximumValue = Float(quantisedMaximumValue + 1) / 166
        
        guard blurHash.count == 4 + 2 * numX * numY else { return nil }
        
        let colours: [SIMD3<Float>] = (0..<numX * numY).map { i in
            if i == 0 {
                let value = String(blurHash[2..<6]).decode83()
                let (r, g, b) = decodeDC(value)
                return SIMD3<Float>(r, g, b)
            } else {
                let start = 4 + i * 2
                let value = String(blurHash[start..<start+2]).decode83()
                let (r, g, b) = decodeAC(value, maximumValue: maximumValue * punch)
                return SIMD3<Float>(r, g, b)
            }
        }
        
        let width: Int = Int(size.width)
        let height: Int = Int(size.height)
        let pixelCount: Int = width * height
        
        var pixels = [SIMD3<UInt8>](repeating: SIMD3<UInt8>(0, 0, 0), count: pixelCount)
        let cosineXTable: [[Float]] = (0..<width).map { x in
            (0..<numX).map { i in
                cos(Float.pi * Float(x) * Float(i) / Float(width))
            }
        }
        
        let cosineYTable: [[Float]] = (0..<height).map { y in
            (0..<numY).map { j in
                cos(Float.pi * Float(y) * Float(j) / Float(height))
            }
        }
        
        pixels.withUnsafeMutableBufferPointer { pixels in
            for y in 0..<height {
                let cosY: [Float] = cosineYTable[y]
                for x in 0..<width {
                    let cosX: [Float] = cosineXTable[x]
                    var color: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
                    
                    for j in 0..<numY {
                        let basisY = cosY[j]
                        for i in 0..<numX {
                            let basis: Float = cosX[i] * basisY
                            // colours are stored in row-major order: index = i + j * numX.
                            color += colours[i + j * numX] * basis
                        }
                    }
                    
                    // Convert from linear space to sRGB.
                    let intR: UInt8 = UInt8(linearTosRGB(color.x))
                    let intG: UInt8 = UInt8(linearTosRGB(color.y))
                    let intB: UInt8 = UInt8(linearTosRGB(color.z))
                    
                    let pixelIndex: Int = x + y * width
                    pixels[pixelIndex] = SIMD3<UInt8>(
                        intR,
                        intG,
                        intB
                    )
                }
            }
        }
        
        let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        guard let provider: CGDataProvider = CGDataProvider(data: NSData(bytes: &pixels, length: pixels.count * 4)) else { return nil }
        guard let cgImage: CGImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        
        return cgImage
    }
}

// MARK: - HELPERS

// MARK: linear <-> sRGB

private func linearTosRGB(_ value: Float) -> Int {
    let v = max(0, min(1, value))
    if v <= 0.0031308 { return Int(v * 12.92 * 255 + 0.5) }
    else { return Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5) }
}

private func sRGBToLinear<Type: BinaryInteger>(_ value: Type) -> Float {
    let v = Float(Int64(value)) / 255
    if v <= 0.04045 { return v / 12.92 }
    else { return pow((v + 0.055) / 1.055, 2.4) }
}

private func sRGBToLinear(_ value: Float) -> Float {
    let v = value / 255.0
    if v <= 0.04045 { return v / 12.92 }
    else { return pow((v + 0.055) / 1.055, 2.4) }
}

private func sRGBToLinear(_ value: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(
        sRGBToLinear(value.x),
        sRGBToLinear(value.y),
        sRGBToLinear(value.z)
    )
}

// MARK: DC & AC Component Encoding/Decoding

private func decodeDC(_ value: Int) -> (Float, Float, Float) {
    let intR = value >> 16
    let intG = (value >> 8) & 255
    let intB = value & 255
    return (sRGBToLinear(intR), sRGBToLinear(intG), sRGBToLinear(intB))
}

private func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
    let quantR = value / (19 * 19)
    let quantG = (value / 19) % 19
    let quantB = value % 19
    
    let rgb = (
        signPow((Float(quantR) - 9) / 9, 2) * maximumValue,
        signPow((Float(quantG) - 9) / 9, 2) * maximumValue,
        signPow((Float(quantB) - 9) / 9, 2) * maximumValue
    )
    
    return rgb
}

private func encodeDC(_ value: SIMD3<Float>) -> Int {
    let roundedR = linearTosRGB(value.x)
    let roundedG = linearTosRGB(value.y)
    let roundedB = linearTosRGB(value.z)
    return (roundedR << 16) + (roundedG << 8) + roundedB
}

private let eighteen: SIMD3<Float> = SIMD3<Float>(18, 18, 18)

private func encodeAC(_ value: SIMD3<Float>, maximumValue: Float) -> Int {
    let floored: SIMD3<Float> = floor(signPow(value / maximumValue, 0.5) * 9 + 9.5)
    let quant: SIMD3<Float> = simd_clamp(floored, .zero, eighteen)
    let quantInt: SIMD3<Int> = SIMD3<Int>(quant)

    return quantInt.x * 19 * 19 + quantInt.y * 19 + quantInt.z
}

// MARK: Power functions

private func signPow(_ value: Float, _ exp: Float) -> Float {
    return copysign(pow(abs(value), exp), value)
}

private func signPow(_ value: SIMD3<Float>, _ exp: Float) -> SIMD3<Float> {
    return SIMD3<Float>(
        signPow(value.x, exp),
        signPow(value.y, exp),
        signPow(value.z, exp)
    )
}

private func pow(_ base: Int, _ exponent: Int) -> Int {
    return (0 ..< exponent).reduce(1) { value, _ in value * base }
}

private func multiplyBasisFunction(pixels: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, bytesPerPixel: Int, pixelOffset: Int, basisFunction: (Float, Float) -> Float) -> (Float, Float, Float) {
    var r: Float = 0
    var g: Float = 0
    var b: Float = 0

    let buffer: UnsafeBufferPointer = UnsafeBufferPointer(start: pixels, count: height * bytesPerRow)

    for x in 0 ..< width {
        for y in 0 ..< height {
            let basis: Float = basisFunction(Float(x), Float(y))
            r += basis * sRGBToLinear(buffer[bytesPerPixel * x + pixelOffset + 0 + y * bytesPerRow])
            g += basis * sRGBToLinear(buffer[bytesPerPixel * x + pixelOffset + 1 + y * bytesPerRow])
            b += basis * sRGBToLinear(buffer[bytesPerPixel * x + pixelOffset + 2 + y * bytesPerRow])
        }
    }

    let scale: Float = 1.0 / Float(width * height)

    return (r * scale, g * scale, b * scale)
}
