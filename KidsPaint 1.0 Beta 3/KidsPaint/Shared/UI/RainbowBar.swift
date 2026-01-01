//
//  RainbowBar.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

/// Vertical rainbow stripes
struct RainbowBar: View {
    var body: some View {
        GeometryReader { geo in
            let stripeCount: CGFloat = 5
            let stripeWidth = geo.size.width / stripeCount

            HStack(spacing: 0) {
                Color(red: 0.95, green: 0.32, blue: 0.26) // red
                    .frame(width: stripeWidth)
                Color(red: 0.98, green: 0.80, blue: 0.18) // yellow
                    .frame(width: stripeWidth)
                Color(red: 0.55, green: 0.78, blue: 0.21) // green
                    .frame(width: stripeWidth)
                Color(red: 0.18, green: 0.67, blue: 0.93) // cyan/blue
                    .frame(width: stripeWidth)
                Color(red: 0.42, green: 0.40, blue: 0.86) // purple
                    .frame(width: stripeWidth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}
