import SwiftUI

struct SelectedSlotRange: Equatable {
    var start: Int
    var end: Int
    var categoryID: String

    var durationMinutes: Int { (end - start) * slotMinutes }
    var startMinutes: Int { start * slotMinutes }
    var endMinutes: Int { end * slotMinutes }
}

/// A 24-hour radial dial you paint with a finger. 00:00 sits at the top and the day
/// runs clockwise (06:00 right, 12:00 bottom, 18:00 left). Dragging around the ring
/// assigns the active category to the swept slots; a nil active category erases.
///
/// The view edits a `[String?]` slot array (`slotsPerDay` entries) bound from the
/// parent, so painting is just writing category ids into slots — overlaps naturally
/// overwrite. The parent converts slots to/from `TimeBlock`s.
struct TimeWheelView: View {
    @Binding var slots: [String?]
    @Binding var selection: SelectedSlotRange?
    let isEditing: Bool
    /// nil id ("消しゴム") erases; otherwise the category being painted.
    let activeCategoryID: String?
    /// Resolves a slot's category id to a color for drawing.
    let colorFor: (String) -> Color
    /// Called once when a drag gesture ends, so the parent can persist.
    var onCommit: () -> Void = {}

    private let thickness: CGFloat = 34
    @State private var lastSlot: Int?
    @State private var dragOrigin: CGPoint?
    @State private var isPainting = false
    @State private var wheelRadius: CGFloat = 0

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                draw(in: &ctx, size: size)
            }
            if isEditing {
                RingHitShape()
                    .fill(.clear)
                    .contentShape(RingHitShape())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let slot = slotIndex(for: value.location) else { return }
                                selectBlock(containing: slot)
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged(handleDrag)
                            .onEnded(handleDragEnd)
                    )
            }
            if isEditing, let selection {
                RangeHandles(
                    selection: Binding(get: { selection }, set: { self.selection = $0 }),
                    slots: $slots,
                    color: colorFor(selection.categoryID),
                    radiusInset: thickness / 2 + 6,
                    onCommit: onCommit
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
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

    private func handleDrag(_ value: DragGesture.Value) {
        if dragOrigin == nil { dragOrigin = value.startLocation }
        guard isOnRing(value.startLocation), isTangentialDrag(value) else { return }
        let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        guard distance > 8 else { return }
        if !isPainting {
            isPainting = true
            selection = nil
            paint(at: value.startLocation)
        }
        paint(at: value.location)
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        if isPainting {
            onCommit()
        }
        lastSlot = nil
        dragOrigin = nil
        isPainting = false
    }

    private func isOnRing(_ point: CGPoint) -> Bool {
        let distance = hypot(point.x - wheelCenter.x, point.y - wheelCenter.y)
        return abs(distance - wheelRadius) <= thickness
    }

    private func isTangentialDrag(_ value: DragGesture.Value) -> Bool {
        let startRadius = hypot(value.startLocation.x - wheelCenter.x, value.startLocation.y - wheelCenter.y)
        let currentRadius = hypot(value.location.x - wheelCenter.x, value.location.y - wheelCenter.y)
        let radialTravel = abs(currentRadius - startRadius)
        let startAngle = atan2(value.startLocation.y - wheelCenter.y, value.startLocation.x - wheelCenter.x)
        let currentAngle = atan2(value.location.y - wheelCenter.y, value.location.x - wheelCenter.x)
        var angleDelta = abs(currentAngle - startAngle)
        if angleDelta > .pi { angleDelta = 2 * .pi - angleDelta }
        let arcTravel = angleDelta * max(1, wheelRadius)
        return arcTravel > max(8, radialTravel * 1.2)
    }

    private func selectBlock(containing slot: Int) {
        guard let categoryID = slots[slot] else {
            selection = nil
            return
        }
        var start = slot
        var end = slot + 1
        while start > 0, slots[start - 1] == categoryID { start -= 1 }
        while end < slots.count, slots[end] == categoryID { end += 1 }
        selection = SelectedSlotRange(start: start, end: end, categoryID: categoryID)
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
        DispatchQueue.main.async { if wheelRadius != radius { wheelRadius = radius } }

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
        let r = radius - thickness / 2 - 12
        for hour in 0..<24 {
            let a = angle(forMinute: hour * 60).radians
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            let resolved = ctx.resolve(
                Text("\(hour)")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.secondary)
            )
            ctx.draw(resolved, at: p)
        }
    }
}

private struct RingHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 2
        let inner = max(0, outer - 58)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: center.x + inner, y: center.y))
        path.addArc(center: center, radius: inner, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct RangeHandles: View {
    @Binding var selection: SelectedSlotRange
    @Binding var slots: [String?]
    let color: Color
    let radiusInset: CGFloat
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side / 2 - radiusInset

            handle(label: "開始", systemImage: "play.fill")
                .position(point(slot: selection.start, center: center, radius: radius))
                .gesture(handleGesture(isStart: true, center: center))

            handle(label: "終了", systemImage: "stop.fill")
                .position(point(slot: selection.end, center: center, radius: radius))
                .gesture(handleGesture(isStart: false, center: center))
        }
        .allowsHitTesting(true)
    }

    private func handle(label: String, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel("\(label)時刻")
    }

    private func handleGesture(isStart: Bool, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in update(isStart: isStart, location: value.location, center: center) }
            .onEnded { _ in onCommit() }
    }

    private func update(isStart: Bool, location: CGPoint, center: CGPoint) {
        var candidate = slot(at: location, center: center)
        if !isStart, selection.end > slotsPerDay / 2, candidate < slotsPerDay / 4 {
            candidate = slotsPerDay
        }
        let old = selection
        let newStart = isStart ? min(candidate, old.end - 1) : old.start
        let newEnd = isStart ? old.end : max(candidate, old.start + 1)
        guard newStart != old.start || newEnd != old.end else { return }

        for index in old.start..<old.end where slots[index] == old.categoryID { slots[index] = nil }
        for index in newStart..<newEnd { slots[index] = old.categoryID }
        selection = SelectedSlotRange(start: newStart, end: newEnd, categoryID: old.categoryID)
    }

    private func slot(at point: CGPoint, center: CGPoint) -> Int {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        return min(slotsPerDay - 1, max(0, Int((angle / (2 * .pi) * Double(slotsPerDay)).rounded())))
    }

    private func point(slot: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double(slot % slotsPerDay) / Double(slotsPerDay) * 2 * Double.pi - Double.pi / 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}
