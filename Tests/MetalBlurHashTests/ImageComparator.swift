//
//  ImageComparator.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 02. 24..
//

import MetalKit

/// An enumeration describing all possible strategies for comparing two images.
public enum ImageComparisonMethod {
    
    /// A per-pixel comparison that allows up to `perPixelTolerance` difference on each channel
    /// and up to `overallTolerance` fraction of differing pixels across the entire image.
    /// - Parameters:
    ///   - perPixelTolerance: The maximum allowed channel difference per pixel in the range [0..1].
    ///   - overallTolerance: The maximum fraction of pixels that can differ in the final comparison [0..1].
    case perPixel(perPixelTolerance: Float, overallTolerance: Double)

    /// A strict, per-pixel comparison that fails if **any** pixel differs.
    case strict

    /// Nested enum describing the revision of the Apple Vision model to use.
    public enum VisionModelRevision {
        case revision1
        case revision2
    }
}

import UIKit

protocol ImageComparison {
    /// Compares 2 images
    /// - Returns:
    ///     Bool value indicating the comparison result, Double value for the percentage of difference based on the comparison method.
    func compareImages(_ image1: UIImage, _ image2: UIImage) -> (Bool, Double)
}

final class ImageComparatorFactory {
    static func createComparator(for method: ImageComparisonMethod) -> ImageComparison {
        switch method {
        case .perPixel(let perPixelTolerance, let overallTolerance):
            if let comparison = PerPixelComparatorMetal(perPixelTolerance: perPixelTolerance, overallTolerance: overallTolerance) {
                return comparison
            }
            return PerPixelComparatorSIMD(perPixelTolerance: perPixelTolerance, overallTolerance: overallTolerance)
        case .strict:
            return StrictComparator()
        }
    }
}

struct PerPixelComparatorMetal: ImageComparison {
    let perPixelTolerance: Float
    let overallTolerance: Double
    let device: MTLDevice
    let function: MTLFunction
    let pipelineState: MTLComputePipelineState
    let commandQueue: MTLCommandQueue

    init?(perPixelTolerance: Float, overallTolerance: Double) {
        self.perPixelTolerance = perPixelTolerance
        self.overallTolerance = overallTolerance
        let device: MTLDevice? = MTLCreateSystemDefaultDevice()
        let library: MTLLibrary? = try? device?.makeLibrary(source:
            """
            #include <metal_stdlib>
            using namespace metal;

            kernel void perPixelCompare(
                device uchar4* image1,
                constant uchar4* image2,
                constant int& perPixelTolerance,
                constant int& width,
                uint2 pid [[thread_position_in_grid]]
            ) {
                uint index = pid.y * width + pid.x;
                int4 a = int4(image1[index]);
                int4 b = int4(image2[index]);
                int4 difference = abs(a - b);
                bool4 isDifferent = difference > perPixelTolerance;
                if (any(isDifferent)) {
                    image1[index] = uchar4(1, 0, 0, 0);
                } else {
                    image1[index] = uchar4(0, 0, 0, 0);
                }
            }
            """, options: .none)
        let function: MTLFunction? = library?.makeFunction(name: "perPixelCompare")
        
        guard let device, let function else {
            return nil
        }
        self.device = device
        self.function = function
        
        let pipelineState: MTLComputePipelineState? = try? device.makeComputePipelineState(function: function)
        let commandQueue: MTLCommandQueue? = device.makeCommandQueue()
        guard let pipelineState, let commandQueue else {
            return nil
        }
        self.pipelineState = pipelineState
        self.commandQueue = commandQueue
    }
    
    func compareImages(_ image1: UIImage, _ image2: UIImage) -> (Bool, Double) {
        guard image1.size == image2.size else {
            assertionFailure("Images must be the same size.")
            return (false, 0)
        }
        guard let cgImage1: CGImage = image1.cgImage, let cgImage2: CGImage = image2.cgImage else {
            assertionFailure("Images must have valid CGImage representations.")
            return (false, 0)
        }
        
        var perPixelToleranceInt: Int = Int((perPixelTolerance * 255).rounded())
    
        let bufferLength: Int = cgImage1.height * cgImage1.bytesPerRow
        let image1Buffer: MTLBuffer? = device.makeBuffer(length: bufferLength)
        let image2Buffer: MTLBuffer? = device.makeBuffer(length: bufferLength)
        let toleranceBuffer: MTLBuffer? = device.makeBuffer(bytes: &perPixelToleranceInt, length: MemoryLayout<Int>.size)
        var width: Int = cgImage1.width
        let widthBuffer: MTLBuffer? = device.makeBuffer(bytes: &width, length: MemoryLayout<Int>.size)
        guard let image1Buffer, let image2Buffer else {
            return fallback(image1, image2)
        }
        
        fillBufferWithImage(cgImage1, buffer: image1Buffer)
        fillBufferWithImage(cgImage2, buffer: image2Buffer)

        let commandBuffer: MTLCommandBuffer? = commandQueue.makeCommandBuffer()
        let commandEncoder: MTLComputeCommandEncoder? = commandBuffer?.makeComputeCommandEncoder()
        guard let commandBuffer, let commandEncoder else {
            return fallback(image1, image2)
        }
        
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(image1Buffer, offset: 0, index: 0)
        commandEncoder.setBuffer(image2Buffer, offset: 0, index: 1)
        commandEncoder.setBuffer(toleranceBuffer, offset: 0, index: 2)
        commandEncoder.setBuffer(widthBuffer, offset: 0, index: 3)
        let imageIndices: Int = cgImage1.width * cgImage1.height
        let gridSize: MTLSize = MTLSize(width: cgImage1.width, height: cgImage1.height, depth: 1)
        let w: Int = pipelineState.threadExecutionWidth
        let h: Int = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup: MTLSize = MTLSize(width: w, height: h, depth: 1)
        commandEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let resultBufferPointer: UnsafeRawBufferPointer = UnsafeRawBufferPointer(start: image1Buffer.contents(), count: bufferLength)
        let result: [UInt32] = Array(resultBufferPointer.bindMemory(to: UInt32.self))
        let badPixels: UInt32 = result.reduce(.zero, +)
        
        let badPixelsRate: Double = Double(badPixels) / Double(imageIndices)
        return (badPixelsRate < overallTolerance, badPixelsRate)
    }
    
    private func fillBufferWithImage(
        _ cgImage: CGImage,
        buffer: MTLBuffer
    ) {
        guard let context = CGContext(
            data: buffer.contents(),
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: cgImage.bytesPerRow,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }
        
        context.draw(
            cgImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: cgImage.width,
                height: cgImage.height
            )
        )
    }
    
    private func fallback(_ image1: UIImage, _ image2: UIImage) -> (Bool, Double) {
        print("Metal failed, Fallback to SIMD")
        let comparison: ImageComparison = PerPixelComparatorSIMD(perPixelTolerance: perPixelTolerance, overallTolerance: overallTolerance)
        return comparison.compareImages(image1, image2)
    }
}

struct PerPixelComparatorSIMD: ImageComparison {
    let perPixelTolerance: Float
    let overallTolerance: Double

    func compareImages(_ image1: UIImage, _ image2: UIImage) -> (Bool, Double) {
        guard image1.size == image2.size else {
            assertionFailure("Images must be the same size.")
            return (false, 0)
        }
        guard let image1: CGImage = image1.cgImage, let image2: CGImage = image2.cgImage else {
            assertionFailure("Images must have valid CGImage representations.")
            return (false, 0)
        }
        
        let totalBytes: Int = image1.height * image1.bytesPerRow

        var image1Pixels: [UInt32] = [UInt32](repeating: 0, count: totalBytes / 4)
        var image2Pixels: [UInt32]  = [UInt32](repeating: 0, count: totalBytes / 4)

        guard let image1Context = CGContext(
            data: &image1Pixels,
            width: Int(image1.width),
            height: Int(image1.height),
            bitsPerComponent: image1.bitsPerComponent,
            bytesPerRow: image1.bytesPerRow,
            space: image1.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image2Context = CGContext(
            data: &image2Pixels,
            width: Int(image2.width),
            height: Int(image2.height),
            bitsPerComponent: image2.bitsPerComponent,
            bytesPerRow: image2.bytesPerRow,
            space: image2.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (false, 1)
        }
        
        image1Context.draw(image1, in: CGRect(x: 0, y: 0, width: image1.width, height: image1.height))
        image2Context.draw(image2, in: CGRect(x: 0, y: 0, width: image2.width, height: image2.height))
        
        let pixelCount: Int = image1.width * image1.height
        var differentPixelCount: Int = 0
        
        image1Pixels.withUnsafeBytes { refBytes in
            image2Pixels.withUnsafeBytes { tarBytes in
                let refPtr: UnsafeBufferPointer<UInt8> = refBytes.bindMemory(to: UInt8.self)
                let tarPtr: UnsafeBufferPointer<UInt8> = tarBytes.bindMemory(to: UInt8.self)
                
                for byteOffset in stride(from: 0, to: pixelCount * 4, by: 4) {
                    
                    let rRef: UInt8 = refPtr[byteOffset + 0]
                    let gRef: UInt8 = refPtr[byteOffset + 1]
                    let bRef: UInt8 = refPtr[byteOffset + 2]
                    let aRef: UInt8 = refPtr[byteOffset + 3]

                    let rTar: UInt8 = tarPtr[byteOffset + 0]
                    let gTar: UInt8 = tarPtr[byteOffset + 1]
                    let bTar: UInt8 = tarPtr[byteOffset + 2]
                    let aTar: UInt8 = tarPtr[byteOffset + 3]
                    
                    let refSIMD: SIMD4<Float> = SIMD4<Float>(Float(rRef), Float(gRef), Float(bRef), Float(aRef))
                    let tarSIMD: SIMD4<Float> = SIMD4<Float>(Float(rTar), Float(gTar), Float(bTar), Float(aTar))
                    
                    let diffSIMD: SIMD4<Float> = abs(refSIMD - tarSIMD)
                    let floatDiff: SIMD4<Float> = diffSIMD / 255.0
                    let exceedMask: SIMDMask<SIMD4<Float.SIMDMaskScalar>> = floatDiff .> SIMD4<Float>(repeating: perPixelTolerance)
                    if exceedMask[0] || exceedMask[1] || exceedMask[2] || exceedMask[3] {
                        differentPixelCount += 1
                    }
                }
            }
        }
                
        return (Double(differentPixelCount) / Double(pixelCount) <= overallTolerance, Double(differentPixelCount) / Double(pixelCount))
    }
}

struct StrictComparator: ImageComparison {
    func compareImages(_ image1: UIImage, _ image2: UIImage) -> (Bool, Double) {
        (image1.pngData() == image2.pngData(), 0)
    }
}
