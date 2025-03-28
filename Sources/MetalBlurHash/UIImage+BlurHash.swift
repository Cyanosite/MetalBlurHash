//
//  UIImage+BlurHash.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 02. 22..
//

import UIKit

extension UIImage {
    /**
     Generates a BlurHash representation of the image.
     
     Use this method to create a string-encoded "blur hash" that represents the image in a compact form.
     This can be useful for showing a placeholder preview (e.g., a blurred rectangle) before the actual
     image is fully loaded.
     
     - Parameters:
        - components: A tuple specifying the number of horizontal and vertical components in the blur hash. For example, (4, 3) means the algorithm samples the image using 4 horizontal and 3 vertical components. A higher number of components typically increases the accuracy but also increases the size of the resulting hash. The **maximum** allowed _value_ of components is **(9, 9)**.
     
     - Returns: A String containing the BlurHash representation of the image, or nil if the operation fails.
     
     ```swift
     // Example usage:
     if let hash = myImage.blurHash(numberOfComponents: (4, 3)) {
     print("Blur Hash:", hash)
     }
     ```
     */
    public func blurHash(numberOfComponents components: (Int, Int)) -> String? {
        MetalBlurHashCoder.encode(self, numberOfComponents: components)
    }
    
    /**
     Creates a `UIImage` from a [BlurHash](https://blurha.sh) string.
     
     This initializer decodes the provided BlurHash string into pixel data and creates
     a `UIImage` of the specified size. The `punch` parameter allows you to adjust
     the contrast of the resulting image.
     
     - Parameters:
        - blurHash: A BlurHash string representing a low-resolution image. Must be at least 6 characters long.
        - size: The desired resolution of the resulting image.
        - punch: A contrast factor applied to the decoded image. Values above `1` increase contrast,
        while values below `1` reduce it. Default is `1`.
     
     - Returns: A `UIImage` if successful, or `nil` if decoding fails (for example, if the BlurHash
     string is malformed or the resulting image data cannot be constructed).
     
     **Example**:
     ```swift
     if let image = UIImage(blurHash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj", size: CGSize(width: 32, height: 32)) {
     // Use the decoded image
     }
     ```
     */
    public convenience init?(blurHash: String, size: CGSize, punch: Float = 1) {
        guard
            let cgImage: CGImage = MetalBlurHashCoder.decode(blurHash: blurHash, size: size, punch: punch)
        else {
            return nil
        }
        self.init(cgImage: cgImage)
    }
}
