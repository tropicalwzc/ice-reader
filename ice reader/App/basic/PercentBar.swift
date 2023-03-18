//
//  PercentBar.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import SwiftUI

struct PerCentBarView: View {
    var percent: CGFloat
    var backColor: Color
    var foreColor: Color
    
    var body: some View {
        ZStack(alignment: .leading) {
            PerCentBar(rate: 1.0).foregroundColor(backColor)
            if percent > 0.02 {
                PerCentBar(rate: percent).foregroundColor(foreColor)
            } else {
                LittleArcPerCentBar(rate: percent).foregroundColor(foreColor)
            }
        }
    }
    
    
    struct PerCentBar : Shape {
        
        var rate : CGFloat
        var lineWidth: CGFloat = 4.0
        
        func path(in rect: CGRect) -> Path {
            var p = Path()
            var barwidth = (rect.width - 2 * lineWidth) * rate
            var realLineWidth = lineWidth
            if barwidth < lineWidth {
                realLineWidth = 0.0
                barwidth = 0.0
            }
            p.addArc(center: CGPoint(x:lineWidth / 2 ,y: lineWidth / 2), radius: lineWidth * 0.5, startAngle: .degrees(270.0), endAngle: .degrees(450.0), clockwise: true)
            p.addLine(to: CGPointMake(realLineWidth, rect.minY + lineWidth))
            p.addArc(center: CGPoint(x:barwidth + lineWidth * 1.5 ,y: lineWidth / 2), radius: lineWidth * 0.5, startAngle: .degrees(90.0), endAngle: .degrees(270.0), clockwise: true)
            p.addLine(to: CGPointMake(lineWidth / 2, rect.minY))
            return p
        }
        
    }
    
    // 只在少于2%使用
    struct LittleArcPerCentBar : Shape {
        
        var rate : CGFloat
        var lineWidth: CGFloat = 4.0
        
        func path(in rect: CGRect) -> Path {
            let innerRate = rate / 0.02
            var p = Path()
            let realLineWidth = lineWidth * innerRate
            p.addArc(center: CGPoint(x:realLineWidth / 2 ,y: lineWidth / 2), radius: realLineWidth * 0.45, startAngle: .degrees(270.0), endAngle: .degrees(450.0), clockwise: true)
            p.addLine(to: CGPointMake(realLineWidth / 2, rect.minY))
            return p
        }
    }
    
}
