//
//  MetalBlurHashCoder.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 03. 08..
//

@preconcurrency import UIKit
import simd

final class MetalBlurHashCoder {
    private struct EncodeParams {
        let width: UInt32
        let height: UInt32
        let bytesPerRow: UInt32
        let cx: UInt32
        let cy: UInt32
    }
    
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    static let library: MTLLibrary? = try? device?.makeDefaultLibrary(bundle: Bundle.module)
    static let commandQueue: MTLCommandQueue? = device?.makeCommandQueue()
    static let encodePipelineState: MTLComputePipelineState? = {
        if let function = library?.makeFunction(name: "encodeBlurHash") {
            return try? device?.makeComputePipelineState(function: function)
        } else {
            return nil
        }
    }()
    static let decodePipelineState: MTLComputePipelineState? = {
        if let function = library?.makeFunction(name: "decodeBlurHash") {
            return try? device?.makeComputePipelineState(function: function)
        } else {
            return nil
        }
    }()
    
    // MARK: - Metal encode
    static func encode(_ image: UIImage, numberOfComponents components: (Int, Int)) -> String? {
        guard components <= (9, 9) else { return nil }
        
        guard
            let device,
            let pipelineState = self.encodePipelineState,
            let commandQueue,
            let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        
        let pixelWidth: Int = Int(round(image.size.width * image.scale))
        let pixelHeight: Int = Int(round(image.size.height * image.scale))
        
        guard let context: CGContext = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: sRGBColorSpace,
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
        
        guard let inputImageBuffer = device.makeBuffer(
            bytes: pixels,
            length: height * bytesPerRow
        ) else {
            return nil
        }

        var factors: [SIMD4<Float>] = [SIMD4<Float>](repeating: .zero, count: components.0 * components.1)

        // MARK: Component factors
        for cy in 0..<components.1 {
            for cx in 0..<components.0 {
                var encodeParams: EncodeParams = EncodeParams(
                    width: UInt32(width),
                    height: UInt32(height),
                    bytesPerRow: UInt32(bytesPerRow),
                    cx: UInt32(cx),
                    cy: UInt32(cy)
                )
                
                guard let paramsBuffer = device.makeBuffer(
                          bytes: &encodeParams,
                          length: MemoryLayout<EncodeParams>.stride
                      ) else {
                    continue
                }
                
                let threadsPerThreadgroup: MTLSize = MTLSize(width: 16, height: 16, depth: 1)
                let threadgroups: MTLSize = MTLSize(
                    width: (width + 15) / 16,
                    height: (height + 15) / 16,
                    depth: 1
                )
                let numThreadgroups: Int = threadgroups.width * threadgroups.height

                guard let resultBuffer = device.makeBuffer(
                          length: MemoryLayout<SIMD4<Float>>.stride * numThreadgroups,
                          options: []
                      ),
                      let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder()
                else {
                    continue
                }
                
                encoder.setComputePipelineState(pipelineState)
                encoder.setBuffer(inputImageBuffer, offset: 0, index: 0)
                encoder.setBuffer(resultBuffer,     offset: 0, index: 1)
                encoder.setBuffer(paramsBuffer,     offset: 0, index: 2)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                encoder.endEncoding()
                
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()

                let partialSums: UnsafeMutablePointer<SIMD4<Float>> = resultBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: numThreadgroups)
                var sum: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0)
                for i in 0..<numThreadgroups {
                    sum += partialSums[i]
                }

                sum *= (1.0 / Float(width * height))
                
                if cx != 0 || cy != 0 {
                    sum *= 2.0
                }
                
                factors[cy * components.0 + cx] = sum
            }
        }
        
        guard let dc: SIMD3<Float> = {
            guard let first = factors.first else { return nil }
            return SIMD3<Float>(x: first.x, y: first.y, z: first.z)
        }() else { return nil }
        let ac: Array<SIMD4<Float>>.SubSequence = factors.dropFirst()
        
        var hash: String = ""
        
        let sizeFlag: Int = (components.0 - 1) + (components.1 - 1) * 9
        hash += sizeFlag.encode83(length: 1)
        
        let maximumValue: Float
        if !ac.isEmpty, let actualMaximumValue = ac.map({ max(abs($0.x), abs($0.y), abs($0.z)) }).max() {
            let quantisedMaximumValue: Int = Int(max(0, min(82, floor(actualMaximumValue * 166 - 0.5))))
            maximumValue = Float(quantisedMaximumValue + 1) / 166
            hash += quantisedMaximumValue.encode83(length: 1)
        } else {
            maximumValue = 1
            hash += 0.encode83(length: 1)
        }
        hash += encodeDC(dc).encode83(length: 4)
        
        for factor in ac {
            let simd3factor: SIMD3<Float> = SIMD3<Float>(x: factor.x, y: factor.y, z: factor.z)
            hash += encodeAC(simd3factor, maximumValue: maximumValue).encode83(length: 2)
        }
        
        return hash
    }
    
    // MARK: - DECODE
    
    private struct DecodeParams {
        let width: UInt32
        let height: UInt32
        let componentsY: UInt32
        let componentsX: UInt32
        let bytesPerRow: UInt32
    }
    
    static func decode(blurHash: String, size: CGSize, punch: Float) -> CGImage? {
        guard blurHash.count >= 6 else { return nil }
        let sizeFlag: Int = String(blurHash[0]).decode83()
        let numY: Int = (sizeFlag / 9) + 1
        let numX: Int = (sizeFlag % 9) + 1
        
        let quantisedMaximumValue: Int = String(blurHash[1]).decode83()
        let maximumValue: Float = Float(quantisedMaximumValue + 1) / 166.0
        
        guard blurHash.count == 4 + 2 * numX * numY else { return nil }
        
        guard let device, let pipelineState = self.decodePipelineState, let commandQueue else {
            return nil
        }
        
        var colors: [SIMD3<Float>] = (0..<numX * numY).map { i in
            if i == 0 {
                let value: Int = String(blurHash[2..<6]).decode83()
                let (r, g, b): (Float, Float, Float) = decodeDC(value)
                return SIMD3<Float>(r, g, b)
            } else {
                let start: Int = 4 + i * 2
                let value: Int = String(blurHash[start..<start+2]).decode83()
                let (r, g, b): (Float, Float, Float) = decodeAC(value, maximumValue: maximumValue * punch)
                return SIMD3<Float>(r, g, b)
            }
        }
        
        let colorsBuffer: MTLBuffer? = device.makeBuffer(bytes: &colors, length: numX * numY * MemoryLayout<SIMD3<Float>>.stride)
        
        let width: Int = Int(size.width)
        let height: Int = Int(size.height)
        let pixelCount: Int = width * height
        
        var decodeParams: DecodeParams = DecodeParams(
            width: UInt32(width),
            height: UInt32(height),
            componentsY: UInt32(numY),
            componentsX: UInt32(numX),
            bytesPerRow: UInt32(width * 4)
        )
        
        let decodeParamsBuffer: MTLBuffer? = device.makeBuffer(bytes: &decodeParams, length: MemoryLayout<DecodeParams>.stride)
        
        
        let pixelsBuffer: MTLBuffer? = device.makeBuffer(length: 4 * pixelCount)
        
        guard
            let colorsBuffer,
            let decodeParamsBuffer,
            let pixelsBuffer,
            let commandBuffer: MTLCommandBuffer = commandQueue.makeCommandBuffer(),
            let commandEncoder: MTLComputeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(colorsBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(pixelsBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(decodeParamsBuffer, offset: 0, index: 2)
        
        let threadsPerThreadgroup: MTLSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups: MTLSize = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        commandEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        guard let provider: CGDataProvider = CGDataProvider(data: NSData(bytes: pixelsBuffer.contents(), length: pixelCount * 4)) else { return nil }
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
