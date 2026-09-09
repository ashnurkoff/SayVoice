import SwiftUI

extension EnvironmentValues {
    /// Draw the glass as the flat `glassFill` tint instead of the live
    /// material. Off screen there is no backdrop to refract, and `glassEffect`
    /// then paints an opaque slab over its own content — which is what the
    /// screenshot harness would capture. Never set in the running app.
    @Entry var dsGlassFallback: Bool = false
}

/// Liquid Glass container for the overlay. Tint, border and top highlight
/// come from tokens; the accent appears here only as the border (one of the
/// three places the accent is allowed).
struct GlassPanel<Content: View>: View {
    enum Shape { case capsule, card }

    let shape: Shape
    @ViewBuilder let content: () -> Content
    @Environment(\.dsGlassFallback) private var flatFill

    init(shape: Shape, @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.content = content
    }

    var body: some View {
        glass(
            content()
                .padding(.horizontal, shape == .capsule ? DS.Space.s16 : DS.Space.s20)
                .padding(.vertical, shape == .capsule ? DS.Space.s12 : DS.Space.s16)
                .frame(width: DS.Size.overlayWidth, alignment: .leading)
        )
            .overlay(clipShape.strokeBorder(DS.Colors.glassLine.color, lineWidth: 1))
            .overlay(alignment: .top) {
                // 1px specular line along the top edge
                clipShape
                    .strokeBorder(
                        LinearGradient(colors: [DS.Colors.glassHighlight.color, .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .mask(alignment: .top) { Rectangle().frame(height: 2) }
            }
            .shadow(color: DS.Colors.glassShadow.color, radius: 25, x: 0, y: 20)
    }

    @ViewBuilder private func glass(_ body: some View) -> some View {
        if flatFill {
            body.background(DS.Colors.glassFill.color, in: clipShape)
        } else {
            body.glassEffect(.regular.tint(DS.Colors.accent.color.opacity(0.10)), in: clipShape)
        }
    }

    private var clipShape: AnyInsettableShape {
        switch shape {
        case .capsule: return AnyInsettableShape(Capsule(style: .continuous))
        case .card:    return AnyInsettableShape(RoundedRectangle(cornerRadius: DS.Radius.overlayCard, style: .continuous))
        }
    }
}

/// Type-erased insettable shape so one `overlay` chain serves both variants.
struct AnyInsettableShape: InsettableShape {
    private let _path: @Sendable (CGRect) -> Path
    private let _inset: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        _path = { shape.path(in: $0) }
        _inset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { _path(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { _inset(amount) }
}
