import SwiftUI

/// A 24-hour radial dial you paint with a finger. 00:00 sits at the top and the day
/// runs clockwise (06:00 right, 12:00 bottom, 18:00 left). Dragging around the ring
/// assigns the active category to the swept slots; a nil active category erases.
///
/// The view edits a `[String?]` slot array (`slotsPerDay` entries) bound from the
/// parent, so painting is just writing category ids into slots — overlaps naturally
/// overwrite. The parent converts slots to/from `TimeBlock`s.
struct TimeWheelView: View {
    @Binding var slots: [String?]
    /// nil id ("消しゴム") erases; otherwise the category being painted.
    let activeCategoryID: String?
    /// Resolves a slot's category id to a color for drawing.
    let colorFor: (String) -> Color
    /// Called once when a drag gesture ends, so the parent can persist.
    var onCommit: () -> Void = {}

    private let thickness: CGFloat = 34
    @State private var lastSlot: Int?

    var body: some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in paint(at: value.location) }
                .onEnded { _ in lastSlot = nil; onCommit() }
        )
        .accessibilityLabel("24時間リング。ドラッグして時間帯にカテゴリを割り当てます。")
    }

    // MARK: - Painting

    private func paint(at point: CGPoint) {
        // Canvas fills the view, so gesture location maps to canvas coordinates; use the
        // square's center regardless of letterboxing from the fixed aspect ratio.
        guard let slot = slotIndex(for: point) else { return }
        if let previous = lastSlot, previous != slot {
            for s in slotsBetween(previous, slot) { slots[s] = activeCategoryID }
        } else {
            slots[slot] = activeCategoryID
        }
        lastSlot = slot
    }

    /// Slots swept between two indices along the shorter arc (inclusive of `to`), so a
    /// fast drag that jumps several slots still fills the gap continuously.
    private func slotsBetween(_ from: Int, _ to: Int) -> [Int] {
        let n = slotsPerDay
        let forward = (to - from + n) % n
        let backward = (from - to + n) % n
        var result: [Int] = []
        if forward <= backward {
            var i = from
            while i != to { i = (i + 1) % n; result.append(i) }
        } else {
            var i = from
            while i != to { i = (i - 1 + n) % n; result.append(i) }
        }
        return result
    }

    private func slotIndex(for point: CGPoint) -> Int? {
        // The Canvas is square-fitted and centered; recover its geometry from the point's
        // container by assuming the drawn square is centered in the view bounds. We only
        // have the point, so derive center from the last known size via the wheel radius.
        // Simplest robust mapping: treat the view as square using the point relative to
        // the midpoint of the gesture's coordinate space, which Canvas provides directly.
        let center = wheelCenter
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        // Ignore touches near the dead center to avoid jittery angle flips.
        guard distance > 8 else { return nil }
        var angle = atan2(dx, -dy)            // 0 at top, clockwise
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)
        return min(slotsPerDay - 1, Int(fraction * Double(slotsPerDay)))
    }

    /// Center of the square wheel. Canvas gives gesture points in its own space whose
    /// size equals the fitted square, so the center is half the min side. We store it
    /// from the last draw.
    @State private var wheelCenter: CGPoint = .zero

    // MARK: - Drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        DispatchQueue.main.async { if wheelCenter != center { wheelCenter = center } }
        let radius = side / 2 - thickness / 2 - 6

        drawTrack(&ctx, center: center, radius: radius)
        drawSegments(&ctx, center: center, radius: radius)
        drawHourTicks(&ctx, center: center, radius: radius)
        drawHourLabels(&ctx, center: center, radius: radius)
    }

    private func angle(forMinute minute: Int) -> Angle {
        Angle(degrees: Double(minute) / 1440 * 360 - 90)
    }

    private func drawTrack(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(path, with: .color(Color.gray.opacity(0.14)),
                   style: StrokeStyle(lineWidth: thickness))
    }

    private func drawSegments(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for block in TimeGrid.blocks(from: slots) {
            var path = Path()
            path.addArc(center: center, radius: radius,
                        startAngle: angle(forMinute: block.start),
                        endAngle: angle(forMinute: block.end), clockwise: false)
            ctx.stroke(path, with: .color(colorFor(block.categoryID)),
                       style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
        }
    }

    private func drawHourTicks(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for hour in 0..<24 {
            let a = angle(forMinute: hour * 60).radians
            let isMajor = hour % 6 == 0
            let inner = radius + thickness / 2 - (isMajor ? 10 : 5)
            let outer = radius + thickness / 2 - 1
            var path = Path()
            path.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
            ctx.stroke(path, with: .color(.white.opacity(isMajor ? 0.9 : 0.5)),
                       style: StrokeStyle(lineWidth: isMajor ? 2 : 1))
        }
    }

    private func drawHourLabels(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let labels: [(Int, String)] = [(0, "0"), (6, "6"), (12, "12"), (18, "18")]
        let r = radius - thickness / 2 - 14
        for (hour, text) in labels {
            let a = angle(forMinute: hour * 60).radians
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            let resolved = ctx.resolve(
                Text(text).font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            )
            ctx.draw(resolved, at: p)
        }
    }
}
