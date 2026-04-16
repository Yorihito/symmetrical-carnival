import SwiftUI

/// iOS / iPadOS 用のカードコンテナ。マテリアル背景とボーダーを付与する。
struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
            )
    }
}
