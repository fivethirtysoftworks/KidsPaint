
//
//  PlatformImage.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    var kp_size: CGSize {
        #if os(macOS)
        return self.size
        #else
        return self.size
        #endif
    }
}

@inline(__always)
func KPImage(_ image: PlatformImage) -> Image {
    #if os(macOS)
    return Image(nsImage: image)
    #else
    return Image(uiImage: image)
    #endif
}
