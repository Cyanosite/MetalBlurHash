# MetalBlurHash

A blazing-fast Metal implementation of the popular [BlurHash](http://blurha.sh) algorithm originally by [Wolt](https://github.com/woltapp/blurhash). This library aims to be a drop-in replacement for Wolt’s BlurHash for Apple platforms, leveraging Metal to provide significant performance boosts while preserving the same results and API usage.

By rewriting key parts of the encoding and decoding routines in Metal, encoding is up to 200× faster, and decoding is up to 125× faster compared to the CPU-based reference implementation.

## Features
- Drop-in replacement
- Metal-accelerated: utilizing your device’s GPU to achieve significant performance gains
- Runs on iOS, MacCatalyst, and VisionOS
- Enables preview generation for each and every image in your app

## Installation

### Swift Package Manager
1.	In Xcode, go to File > Add Packages…
2.	Enter the repository URL of MetalBlurHash.
3.	Choose the version you want to install.
4.	In your Swift files, simply import the framework:

```swift
import MetalBlurHash
```

## Usage

### Encoding

```swift
import MetalBlurHash

// Suppose you have a UIImage named `image`
let blurHash: String = image.blurHash(numberOfComponents: (9, 9))
```

### Decoding

```swift
import MetalBlurHash

let blurHashString = "|lM~Oi00%#Mwo}wbtRjFoeS|WDWEIoa$s.WBa#niR*X8R*bHbIawt7aeWVRjofs.R*R+axR+WBofs:ofjsofbFWBflfjogs:jsWCfQjZWCbHkCWVWVjbjtjsjsa|ayj@j[oLj[a|j?j[jZoLayWVWBayj[jtf6azWCafoL"
let decodedImage: UIImage = UIImage(blurHash: blurHash, size: CGSize(width: 3840, height: 2160))
```

> [!NOTE]
> The blurHash in this sample code has 9 × 9 components and can be decoded.

## Performance Benchmarks

Below are indicative benchmarks measured on an M1 Max. Results will vary based on device, image sizes, and the number of components used. Nonetheless, you should expect a ~200× speedup for encoding and a ~15× speedup for decoding in typical usage scenarios.

#### Test parameters
|  Task  |  Resolution | Components |
| :----- | :---------: | :--------: |
| Encode | 3648 × 5472 |    9 × 9   |
| Decode | 3840 × 2560 |    9 × 9   |

#### Test result
|  Task  | Original | MetalBlurHash | Speedup |
| :----- | :------: | :-----------: | :-----: |
| Encode |  32.380s |     0.172s    |  200×   |
| Decode |  3.372s  |     0.027s    |  125×   |

(Times and multipliers are illustrative. Actual performance will depend on your hardware and usage patterns.)

> [!TIP]
> You may verify these results on your own hardware with your own parameters using the unit tests in the repository.

### License

MetalBlurHash is released under the MIT License. It is in no way affiliated with Wolt, although it is inspired by and references their original BlurHash work.
