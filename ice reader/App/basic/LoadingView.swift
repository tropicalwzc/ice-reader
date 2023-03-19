//
//  LoadingView.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/19.
//

import SwiftUI

struct LoadingView: View {
    @State private var isLoading = false
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var reverse : CGFloat = 1.0
    var body: some View {
        VStack {
            Text("加载中...")
                .font(.system(.body, design: .rounded))
                .bold()
                .padding(.top, 40)
    
            ZStack {
                
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 14)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0 , to: 0.2)
                    .stroke(Color.init("Indicator"), lineWidth: 7)
                    .frame(width: 100, height: 100)
                    .rotationEffect(Angle(degrees: isLoading ? 360 + reverse : 0 - reverse))
                
            }
                
        }
        .onAppear {
            self.isLoading = true
        }
        .onReceive(timer) { _ in

                if reverse == 0 {
                    reverse = -360
                } else {
                    reverse = 0
                }
            
            withAnimation(.easeInOut(duration: 0.6)) {
                isLoading.toggle()
            }
        }
    }
}
