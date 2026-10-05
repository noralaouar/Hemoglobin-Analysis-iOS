
import SwiftUI

struct ROISelectorView: View {
    @Binding var roi: CGRect
    @State private var lastDragValue: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0

    /// Prevent ROI from collapsing to almost zero (in pixels).
    private let minSize: CGFloat = 30

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: roi.width, height: roi.height)
                .position(x: roi.midX, y: roi.midY)
                // Drag
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let t = value.translation
                            roi.origin.x += t.width - lastDragValue.width
                            roi.origin.y += t.height - lastDragValue.height
                            lastDragValue = t
                        }
                        .onEnded { _ in
                            lastDragValue = .zero
                        }
                )
                // Pinch (simultaneous so it doesn't override drag)
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            let factor = scale / lastScale
                            var newW = roi.width * factor
                            var newH = roi.height * factor

                            newW = max(minSize, newW)
                            newH = max(minSize, newH)

                            roi = CGRect(
                                x: roi.midX - newW / 2,
                                y: roi.midY - newH / 2,
                                width: newW,
                                height: newH
                            )
                            lastScale = scale
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
        }
        .allowsHitTesting(true)
    }
}
