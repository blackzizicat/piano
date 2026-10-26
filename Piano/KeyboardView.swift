import UIKit

/// Piano keyboard (A0...C8) showing 14 white keys (two octaves) at a time.
/// Touching a key sounds it immediately; dragging horizontally beyond a small
/// threshold releases that note and scrolls the keyboard instead.
final class KeyboardView: UIView {
    var onNoteOn: ((Int, Float) -> Void)?
    var onNoteOff: ((Int) -> Void)?

    private struct Key {
        let note: Int
        let whiteIndex: Int   // white key: own index; black key: index of the white key to its left
        let layer: CALayer
    }

    private struct TouchInfo {
        var note: Int?
        var startX: CGFloat
        var startOffset: CGFloat
        var scrolling: Bool
    }

    private static let visibleWhiteKeys: CGFloat = 14
    private static let scrollThreshold: CGFloat = 14
    private static let initialNote = 48   // C3 -> shows C3...B4

    private var whiteKeys: [Key] = []
    private var blackKeys: [Key] = []
    private var layerByNote = [CALayer?](repeating: nil, count: 128)
    private var labels: [CATextLayer] = []
    private var pressCount = [Int](repeating: 0, count: 128)
    private var activeTouches: [ObjectIdentifier: TouchInfo] = [:]

    private var offset: CGFloat = 0
    private var didSetInitialOffset = false

    private var whiteWidth: CGFloat { bounds.width / KeyboardView.visibleWhiteKeys }
    private var blackWidth: CGFloat { whiteWidth * 0.6 }
    private var blackHeight: CGFloat { bounds.height * 0.62 }
    private var maxOffset: CGFloat {
        max(0, CGFloat(whiteKeys.count) * whiteWidth - bounds.width)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .black
        isMultipleTouchEnabled = true
        isExclusiveTouch = false

        let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]
        for note in PianoSynth.firstNote...PianoSynth.lastNote {
            let layer = CALayer()
            layerByNote[note] = layer
            if blackPitchClasses.contains(note % 12) {
                layer.cornerRadius = 3
                layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                blackKeys.append(Key(note: note, whiteIndex: whiteKeys.count - 1, layer: layer))
            } else {
                layer.cornerRadius = 4
                layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                whiteKeys.append(Key(note: note, whiteIndex: whiteKeys.count, layer: layer))
                if note % 12 == 0 {
                    let text = CATextLayer()
                    text.string = "C\(note / 12 - 1)"
                    text.fontSize = 11
                    text.alignmentMode = .center
                    text.foregroundColor = UIColor.gray.cgColor
                    text.contentsScale = UIScreen.main.scale
                    layer.addSublayer(text)
                    labels.append(text)
                }
            }
            updateColor(note: note)
        }
        whiteKeys.forEach { self.layer.addSublayer($0.layer) }
        blackKeys.forEach { self.layer.addSublayer($0.layer) }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if !didSetInitialOffset, bounds.width > 0 {
            didSetInitialOffset = true
            if let idx = whiteKeys.firstIndex(where: { $0.note == KeyboardView.initialNote }) {
                offset = CGFloat(idx) * whiteWidth
            }
        }
        offset = min(max(offset, 0), maxOffset)
        layoutKeys()
    }

    private func layoutKeys() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = whiteWidth
        let h = bounds.height
        for key in whiteKeys {
            key.layer.frame = CGRect(x: CGFloat(key.whiteIndex) * w - offset + 0.5, y: 0, width: w - 1, height: h)
        }
        let bw = blackWidth
        for key in blackKeys {
            let x = CGFloat(key.whiteIndex + 1) * w - bw / 2 - offset
            key.layer.frame = CGRect(x: x, y: 0, width: bw, height: blackHeight)
        }
        for text in labels {
            text.frame = CGRect(x: 0, y: h - 22, width: w - 1, height: 16)
        }
        CATransaction.commit()
    }

    private func setOffset(_ value: CGFloat) {
        let clamped = min(max(value, 0), maxOffset)
        if clamped == offset { return }
        offset = clamped
        layoutKeys()
    }

    private func updateColor(note: Int) {
        guard let layer = layerByNote[note] else { return }
        let black = [1, 3, 6, 8, 10].contains(note % 12)
        let pressed = pressCount[note] > 0
        let color: UIColor
        if black {
            color = pressed ? UIColor(red: 0.25, green: 0.5, blue: 0.9, alpha: 1) : UIColor(white: 0.1, alpha: 1)
        } else {
            color = pressed ? UIColor(red: 0.7, green: 0.82, blue: 1, alpha: 1) : .white
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    // MARK: - Hit testing

    private func note(at point: CGPoint) -> Int? {
        let cx = point.x + offset
        let w = whiteWidth
        if point.y < blackHeight {
            let bw = blackWidth
            for key in blackKeys {
                let x = CGFloat(key.whiteIndex + 1) * w - bw / 2
                if cx >= x && cx < x + bw { return key.note }
            }
        }
        let idx = Int(floor(cx / w))
        guard idx >= 0, idx < whiteKeys.count else { return nil }
        return whiteKeys[idx].note
    }

    private func press(_ note: Int, at point: CGPoint) {
        pressCount[note] += 1
        if pressCount[note] == 1 {
            let ratio = Float(min(max(point.y / max(bounds.height, 1), 0), 1))
            onNoteOn?(note, 0.5 + 0.5 * ratio)
            updateColor(note: note)
        }
    }

    private func release(_ note: Int) {
        guard pressCount[note] > 0 else { return }
        pressCount[note] -= 1
        if pressCount[note] == 0 {
            onNoteOff?(note)
            updateColor(note: note)
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            let n = note(at: p)
            activeTouches[ObjectIdentifier(touch)] = TouchInfo(note: n, startX: p.x, startOffset: offset, scrolling: false)
            if let n = n { press(n, at: p) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard var info = activeTouches[id] else { continue }
            let x = touch.location(in: self).x
            if info.scrolling {
                setOffset(info.startOffset - (x - info.startX))
            } else if abs(x - info.startX) > KeyboardView.scrollThreshold {
                info.scrolling = true
                if let n = info.note { release(n) }
                info.note = nil
                info.startX = x
                info.startOffset = offset
            }
            activeTouches[id] = info
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if let info = activeTouches.removeValue(forKey: id), let n = info.note {
                release(n)
            }
        }
    }
}
