// MapView.swift — zoomable / scrollable city map for iPadOS (UIScrollView)
// and macOS (NSScrollView). One finger / mouse button applies the tool;
// two fingers / trackpad scroll / right-drag pan the map; pinch zooms.
// Part of a modified version of Micropolis (GPL-3.0).

import SwiftUI
import QuartzCore

private let tilePt: CGFloat = 16
private var mapSize: CGSize { CGSize(width: CGFloat(MPWorldWidth) * tilePt, height: CGFloat(MPWorldHeight) * tilePt) }

/// Rectangle (in map points) that the current tool would cover at a tile.
@MainActor
func toolPreviewRect(tool: MPTool, x: Int, y: Int) -> CGRect {
    let size = MPEngine.size(of: tool)
    let origin = size > 1 ? 1 : 0
    return CGRect(x: CGFloat(x - origin) * tilePt, y: CGFloat(y - origin) * tilePt,
                  width: CGFloat(size) * tilePt, height: CGFloat(size) * tilePt)
}

/// Layers shared by both platforms.
@MainActor
final class MapLayers {
    let image = CALayer()
    let preview = CAShapeLayer()

    init() {
        image.magnificationFilter = .nearest
        image.minificationFilter = .linear
        image.frame = CGRect(origin: .zero, size: mapSize)
        image.backgroundColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        image.actions = ["contents": NSNull()]
        preview.fillColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)
        preview.strokeColor = CGColor(red: 1, green: 0.85, blue: 0.1, alpha: 1)
        preview.lineWidth = 1.5
        preview.actions = ["path": NSNull(), "hidden": NSNull()]
        preview.isHidden = true
    }

    func showPreview(_ rect: CGRect?) {
        if let rect {
            preview.path = CGPath(rect: rect, transform: nil)
            preview.isHidden = false
        } else {
            preview.isHidden = true
        }
    }
}

func tileAt(_ p: CGPoint) -> (Int, Int) {
    (Int(floor(p.x / tilePt)), Int(floor(p.y / tilePt)))
}

#if os(iOS)
import UIKit

struct MapView: UIViewRepresentable {
    let model: GameModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> UIScrollView {
        let c = context.coordinator
        let scroll = UIScrollView()
        scroll.delegate = c
        scroll.backgroundColor = .black
        scroll.minimumZoomScale = 0.4
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = true
        scroll.contentInsetAdjustmentBehavior = .never
        // One finger is for building; two fingers scroll.
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        scroll.panGestureRecognizer.allowedScrollTypesMask = .all

        let content = UIView(frame: CGRect(origin: .zero, size: mapSize))
        content.layer.addSublayer(c.layers.image)
        content.layer.addSublayer(c.layers.preview)
        scroll.addSubview(content)
        scroll.contentSize = mapSize
        c.content = content
        c.scroll = scroll

        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.allowedScrollTypesMask = []
        content.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleTap(_:)))
        content.addGestureRecognizer(tap)
        let hover = UIHoverGestureRecognizer(target: c, action: #selector(Coordinator.handleHover(_:)))
        content.addGestureRecognizer(hover)

        scroll.zoomScale = 1.0
        c.layers.image.contents = model.mapImage
        model.frameSink = { [weak c] img in c?.layers.image.contents = img }
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let c = context.coordinator
        if let req = model.focusRequest, req != c.lastFocus {
            c.lastFocus = req
            c.focus(x: req.x, y: req.y)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let model: GameModel
        let layers = MapLayers()
        weak var content: UIView?
        weak var scroll: UIScrollView?
        var lastFocus: FocusRequest?

        init(model: GameModel) { self.model = model }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

        func centerContent() {
            guard let scroll, let content else { return }
            let bw = scroll.bounds.width, bh = scroll.bounds.height
            let cw = content.frame.width, ch = content.frame.height
            scroll.contentInset = UIEdgeInsets(top: max(0, (bh - ch) / 2), left: max(0, (bw - cw) / 2),
                                               bottom: 0, right: 0)
        }

        func focus(x: Int, y: Int) {
            guard let scroll else { return }
            centerContent()
            let z = scroll.zoomScale
            let target = CGPoint(x: (CGFloat(x) + 0.5) * tilePt * z - scroll.bounds.width / 2,
                                 y: (CGFloat(y) + 0.5) * tilePt * z - scroll.bounds.height / 2)
            let maxX = max(0, scroll.contentSize.width - scroll.bounds.width)
            let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: min(max(-scroll.contentInset.left, target.x), maxX),
                                            y: min(max(-scroll.contentInset.top, target.y), maxY)),
                                    animated: true)
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let content else { return }
            let (x, y) = tileAt(g.location(in: content))
            switch g.state {
            case .began:
                layers.showPreview(toolPreviewRect(tool: model.tool, x: x, y: y))
                model.toolBegan(x: x, y: y)
            case .changed:
                layers.showPreview(toolPreviewRect(tool: model.tool, x: x, y: y))
                model.toolMoved(x: x, y: y)
            case .ended:
                model.toolEnded(x: x, y: y)
                layers.showPreview(nil)
            default:
                model.toolCancelled()
                layers.showPreview(nil)
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let content else { return }
            let (x, y) = tileAt(g.location(in: content))
            model.toolBegan(x: x, y: y)
            model.toolEnded(x: x, y: y)
        }

        @objc func handleHover(_ g: UIHoverGestureRecognizer) {
            guard let content else { return }
            switch g.state {
            case .began, .changed:
                let (x, y) = tileAt(g.location(in: content))
                layers.showPreview(toolPreviewRect(tool: model.tool, x: x, y: y))
            default:
                layers.showPreview(nil)
            }
        }
    }
}

#elseif os(macOS)
import AppKit

final class MapNSView: NSView {
    var layers: MapLayers!
    weak var model: GameModel?
    private var dragging = false
    private var panStart: NSPoint?
    private var panOrigin: NSPoint = .zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func tile(_ e: NSEvent) -> (Int, Int) { tileAt(convert(e.locationInWindow, from: nil)) }

    private func preview(_ e: NSEvent) {
        guard let model else { return }
        let (x, y) = tile(e)
        layers.showPreview(toolPreviewRect(tool: model.tool, x: x, y: y))
    }

    override func mouseMoved(with e: NSEvent) { preview(e) }
    override func mouseExited(with e: NSEvent) { layers.showPreview(nil) }

    override func mouseDown(with e: NSEvent) {
        guard let model else { return }
        dragging = true
        let (x, y) = tile(e)
        preview(e)
        model.toolBegan(x: x, y: y)
    }

    override func mouseDragged(with e: NSEvent) {
        guard let model, dragging else { return }
        autoscroll(with: e)
        let (x, y) = tile(e)
        preview(e)
        model.toolMoved(x: x, y: y)
    }

    override func mouseUp(with e: NSEvent) {
        guard let model, dragging else { return }
        dragging = false
        let (x, y) = tile(e)
        model.toolEnded(x: x, y: y)
    }

    // Right / middle drag pans the map.
    override func rightMouseDown(with e: NSEvent) { beginPan(e) }
    override func rightMouseDragged(with e: NSEvent) { continuePan(e) }
    override func otherMouseDown(with e: NSEvent) { beginPan(e) }
    override func otherMouseDragged(with e: NSEvent) { continuePan(e) }

    private func beginPan(_ e: NSEvent) {
        panStart = e.locationInWindow
        panOrigin = enclosingScrollView?.contentView.bounds.origin ?? .zero
        NSCursor.closedHand.push()
    }

    private func continuePan(_ e: NSEvent) {
        guard let start = panStart, let clip = enclosingScrollView?.contentView else { return }
        let mag = enclosingScrollView?.magnification ?? 1
        let dx = (e.locationInWindow.x - start.x) / mag
        let dy = (e.locationInWindow.y - start.y) / mag
        clip.scroll(to: NSPoint(x: panOrigin.x - dx, y: panOrigin.y + dy))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    override func rightMouseUp(with e: NSEvent) { panStart = nil; NSCursor.pop() }
    override func otherMouseUp(with e: NSEvent) { panStart = nil; NSCursor.pop() }
}

struct MapView: NSViewRepresentable {
    let model: GameModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.4
        scroll.maxMagnification = 4
        scroll.backgroundColor = .black
        scroll.drawsBackground = true

        let view = MapNSView(frame: CGRect(origin: .zero, size: mapSize))
        view.wantsLayer = true
        view.layers = c.layers
        view.model = model
        view.layer?.addSublayer(c.layers.image)
        view.layer?.addSublayer(c.layers.preview)
        scroll.documentView = view
        c.scroll = scroll
        c.layers.image.contents = model.mapImage
        model.frameSink = { [weak c] img in c?.layers.image.contents = img }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        if let req = model.focusRequest, req != c.lastFocus {
            c.lastFocus = req
            c.focus(x: req.x, y: req.y)
        }
    }

    @MainActor
    final class Coordinator {
        let layers = MapLayers()
        weak var scroll: NSScrollView?
        var lastFocus: FocusRequest?

        func focus(x: Int, y: Int) {
            guard let scroll else { return }
            let visible = scroll.contentView.bounds.size
            let p = NSPoint(x: (CGFloat(x) + 0.5) * tilePt - visible.width / 2,
                            y: (CGFloat(y) + 0.5) * tilePt - visible.height / 2)
            let maxX = max(0, mapSize.width - visible.width)
            let maxY = max(0, mapSize.height - visible.height)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                scroll.contentView.animator().setBoundsOrigin(NSPoint(x: min(max(0, p.x), maxX),
                                                                       y: min(max(0, p.y), maxY)))
            }
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
#endif
