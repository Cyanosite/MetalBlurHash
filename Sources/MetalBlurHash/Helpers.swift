//
//  Helpers.swift
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 03. 12..
//

import Foundation
import simd

// MARK: - Base83

private let encodeCharacters: [String] = {
    return "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~".map { String($0) }
}()

private let decodeCharacters: [String: Int] = {
    var dict: [String: Int] = [:]
    for (index, character) in encodeCharacters.enumerated() {
        dict[character] = index
    }
    return dict
}()

extension BinaryInteger {
    func encode83(length: Int) -> String {
        var result: String = ""
        for i: Int in 1 ... length {
            let digit: Int = (Int(self) / pow(83, length - i)) % 83
            result += encodeCharacters[Int(digit)]
        }
        return result
    }
}

extension String {
    func decode83() -> Int {
        var value: Int = 0
        for character in self {
            if let digit = decodeCharacters[String(character)] {
                value = value * 83 + digit
            }
        }
        return value
    }
}

// MARK: linear <-> sRGB

func linearTosRGB(_ value: Float) -> Int {
    let v: Float = max(0, min(1, value))
    if v <= 0.0031308 { return Int(v * 12.92 * 255 + 0.5) }
    else { return Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5) }
}

func sRGBToLinear<Type: BinaryInteger>(_ value: Type) -> Float {
    let v: Float = Float(Int64(value)) / 255
    if v <= 0.04045 { return v / 12.92 }
    else { return pow((v + 0.055) / 1.055, 2.4) }
}

// MARK: DC & AC Component Encoding/Decoding

func decodeDC(_ value: Int) -> (Float, Float, Float) {
    let intR: Int = value >> 16
    let intG: Int = (value >> 8) & 255
    let intB: Int = value & 255
    return (sRGBToLinear(intR), sRGBToLinear(intG), sRGBToLinear(intB))
}

func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
    let quantR: Int = value / (19 * 19)
    let quantG: Int = (value / 19) % 19
    let quantB: Int = value % 19
    
    let rgb: (Float, Float, Float) = (
        signPow((Float(quantR) - 9) / 9, 2) * maximumValue,
        signPow((Float(quantG) - 9) / 9, 2) * maximumValue,
        signPow((Float(quantB) - 9) / 9, 2) * maximumValue
    )
    
    return rgb
}

func encodeDC(_ value: (Float, Float, Float)) -> Int {
    let roundedR: Int = linearTosRGB(value.0)
    let roundedG: Int = linearTosRGB(value.1)
    let roundedB: Int = linearTosRGB(value.2)
    return (roundedR << 16) + (roundedG << 8) + roundedB
}

func encodeAC(_ value: (Float, Float, Float), maximumValue: Float) -> Int {
    let quantR: Int = Int(max(0, min(18, floor(signPow(value.0 / maximumValue, 0.5) * 9 + 9.5))))
    let quantG: Int = Int(max(0, min(18, floor(signPow(value.1 / maximumValue, 0.5) * 9 + 9.5))))
    let quantB: Int = Int(max(0, min(18, floor(signPow(value.2 / maximumValue, 0.5) * 9 + 9.5))))

    return quantR * 19 * 19 + quantG * 19 + quantB
}

// MARK: Power functions

func signPow(_ value: Float, _ exp: Float) -> Float {
    return copysign(pow(abs(value), exp), value)
}

func pow(_ base: Int, _ exponent: Int) -> Int {
    return (0 ..< exponent).reduce(1) { value, _ in value * base }
}

// MARK: - SIMD Helpers

func encodeDC(_ value: SIMD3<Float>) -> Int {
    let roundedR: Int = linearTosRGB(value.x)
    let roundedG: Int = linearTosRGB(value.y)
    let roundedB: Int = linearTosRGB(value.z)
    return (roundedR << 16) + (roundedG << 8) + roundedB
}

private let eighteen: SIMD3<Float> = SIMD3<Float>(18, 18, 18)

func encodeAC(_ value: SIMD3<Float>, maximumValue: Float) -> Int {
    let floored: SIMD3<Float> = floor(signPowSIMD(value / maximumValue, 0.5) * 9 + 9.5)
    let quant: SIMD3<Float> = simd_clamp(floored, .zero, eighteen)
    let quantInt: SIMD3<Int> = SIMD3<Int>(quant)

    return quantInt.x * 19 * 19 + quantInt.y * 19 + quantInt.z
}

func signPowSIMD(_ value: SIMD3<Float>, _ exp: Float) -> SIMD3<Float> {
    return SIMD3<Float>(
        signPow(value.x, exp),
        signPow(value.y, exp),
        signPow(value.z, exp)
    )
}

// MARK: String

extension String {
    subscript (offset: Int) -> Character {
        return self[index(startIndex, offsetBy: offset)]
    }

    subscript (bounds: CountableClosedRange<Int>) -> Substring {
        let start: String.Index = index(startIndex, offsetBy: bounds.lowerBound)
        let end: String.Index = index(startIndex, offsetBy: bounds.upperBound)
        return self[start...end]
    }

    subscript (bounds: CountableRange<Int>) -> Substring {
        let start: String.Index = index(startIndex, offsetBy: bounds.lowerBound)
        let end: String.Index = index(startIndex, offsetBy: bounds.upperBound)
        return self[start..<end]
    }
}
