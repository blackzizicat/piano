import UIKit

/// Piano keyboard (A0...C8) showing 14 white keys (two octaves) at a time.
/// Touching a key sounds it immediately; dragging horizontally beyond a small
/// threshold also scrolls the keyboard while the note keeps sounding.
final class KeyboardView: UIView {
    var onNoteOn: ((Int, Float) -> Void)?
    var onNoteOff: ((Int) -> Void)?

    private final class Key {
        let note: Int
        let isBlack: Bool
        let whiteIndex: Int            // white key: own index; black key: index of the white key to its left
        let container = CALayer()      // positioned layer; carries the drop shadow for black keys
        let body = CAGradientLayer()
        let face = CAGradientLayer()   // top surface of a black key

        init(note: Int, isBlack: Bool, whiteIndex: Int) {
            self.note = note
            self.isBlack = isBlack
            self.whiteIndex = whiteIndex
        }
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
    private var keyByNote = [Key?](repeating: nil, count: 128)
    private var pressCount = [Int](repeating: 0, count: 128)
    private var activeTouches: [ObjectIdentifier: TouchInfo] = [:]
    private var scrollDriver: ObjectIdentifier?   // only one finger drives scrolling at a time

    private let felt = CAGradientLayer()

    private var offset: CGFloat = 0
    private var didSetInitialOffset = false
    private var lastSize: CGSize = .zero

    private var whiteWidth: CGFloat { bounds.width / KeyboardView.visibleWhiteKeys }
    private var blackWidth: CGFloat { whiteWidth * 0.58 }
    private var blackHeight: CGFloat { bounds.height * 0.63 }
    private var feltHeight: CGFloat { max(4, bounds.height * 0.025) }
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
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false

        let bottomCorners: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]
        for note in PianoSynth.firstNote...PianoSynth.lastNote {
            let isBlack = blackPitchClasses.contains(note % 12)
            let key = Key(note: note, isBlack: isBlack,
                          whiteIndex: isBlack ? whiteKeys.count - 1 : whiteKeys.count)
            key.body.masksToBounds = true
            key.body.maskedCorners = bottomCorners
            key.container.addSublayer(key.body)
            if isBlack {
                key.body.cornerRadius = 2
                key.body.startPoint = CGPoint(x: 0, y: 0.5)
                key.body.endPoint = CGPoint(x: 1, y: 0.5)
                key.body.colors = [gray(0.02), gray(0.16), gray(0.10), gray(0.02)]
                key.body.locations = [0, 0.25, 0.75, 1]
                key.face.cornerRadius = 1.5
                key.face.maskedCorners = bottomCorners
                key.container.addSublayer(key.face)
                key.container.shadowColor = UIColor.black.cgColor
                key.container.shadowOpacity = 0.55
                key.container.shadowRadius = 2.5
                key.container.shadowOffset = CGSize(width: 1.5, height: 2)
                blackKeys.append(key)
            } else {
                key.body.cornerRadius = 3
                whiteKeys.append(key)
            }
            keyByNote[note] = key
        }
        whiteKeys.forEach { layer.addSublayer($0.container) }
        blackKeys.forEach { layer.addSublayer($0.container) }

        // Red felt strip along the back edge of the keys.
        felt.colors = [UIColor(red: 0.25, green: 0.02, blue: 0.04, alpha: 1).cgColor,
                       UIColor(red: 0.50, green: 0.06, blue: 0.09, alpha: 1).cgColor]
        felt.shadowColor = UIColor.black.cgColor
        felt.shadowOpacity = 0.5
        felt.shadowRadius = 3
        felt.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(felt)

        for note in PianoSynth.firstNote...PianoSynth.lastNote { updateAppearance(note: note) }
    }

    private func gray(_ white: CGFloat) -> CGColor {
        UIColor(white: white, alpha: 1).cgColor
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
        if bounds.size != lastSize {
            lastSize = bounds.size
            resizeKeys()
        }
        layoutKeys()
    }

    /// Updates everything that depends only on the view size (not on scrolling).
    private func resizeKeys() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let whiteSize = CGSize(width: whiteWidth - 1, height: bounds.height)
        for key in whiteKeys {
            key.container.bounds = CGRect(origin: .zero, size: whiteSize)
            key.body.frame = key.container.bounds
        }
        let blackSize = CGSize(width: blackWidth, height: blackHeight)
        for key in blackKeys {
            key.container.bounds = CGRect(origin: .zero, size: blackSize)
            key.body.frame = key.container.bounds
            key.container.shadowPath = UIBezierPath(roundedRect: key.container.bounds, cornerRadius: 2).cgPath
            updateAppearance(note: key.note)
        }
        felt.frame = CGRect(x: 0, y: 0, width: bounds.width, height: feltHeight)
        CATransaction.commit()
    }

    private func layoutKeys() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = whiteWidth
        for key in whiteKeys {
            key.container.frame.origin = CGPoint(x: CGFloat(key.whiteIndex) * w - offset + 0.5, y: 0)
        }
        let bw = blackWidth
        for key in blackKeys {
            key.container.frame.origin = CGPoint(x: CGFloat(key.whiteIndex + 1) * w - bw / 2 - offset, y: 0)
        }
        CATransaction.commit()
    }

    private func setOffset(_ value: CGFloat) {
        let clamped = min(max(value, 0), maxOffset)
        if clamped == offset { return }
        offset = clamped
        layoutKeys()
    }

    private func updateAppearance(note: Int) {
        guard let key = keyByNote[note] else { return }
        let pressed = pressCount[note] > 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if key.isBlack {
            // The top face reaches further toward the front edge when the key is pushed down.
            let size = key.container.bounds.size
            let inset = size.width * 0.12
            let front = size.height * (pressed ? 0.04 : 0.09)
            key.face.frame = CGRect(x: inset, y: 0, width: size.width - inset * 2, height: size.height - front)
            key.face.colors = pressed
                ? [gray(0.04), gray(0.10), gray(0.16)]
                : [gray(0.10), gray(0.18), gray(0.30)]
            key.face.locations = [0, 0.85, 1]
        } else {
            // Ivory surface, shaded under the felt and toward the front edge.
            key.body.colors = pressed
                ? [gray(0.62), gray(0.84), gray(0.90), gray(0.80)]
                : [gray(0.80), gray(0.97), gray(1.00), gray(0.88)]
            key.body.locations = pressed ? [0, 0.12, 0.96, 1] : [0, 0.06, 0.97, 1]
        }
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

    private func press(_ note: Int) {
        pressCount[note] += 1
        if pressCount[note] == 1 {
            onNoteOn?(note, 0.8)
            updateAppearance(note: note)
        }
    }

    private func release(_ note: Int) {
        guard pressCount[note] > 0 else { return }
        pressCount[note] -= 1
        if pressCount[note] == 0 {
            onNoteOff?(note)
            updateAppearance(note: note)
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            let n = note(at: p)
            activeTouches[ObjectIdentifier(touch)] = TouchInfo(note: n, startX: p.x, startOffset: offset, scrolling: false)
            if let n = n { press(n) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard var info = activeTouches[id] else { continue }
            let x = touch.location(in: self).x
            if info.scrolling {
                if scrollDriver == id { setOffset(info.startOffset - (x - info.startX)) }
            } else if abs(x - info.startX) > KeyboardView.scrollThreshold {
                info.scrolling = true
                info.startX = x
                info.startOffset = offset
                scrollDriver = id
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
            if scrollDriver == id { scrollDriver = nil }
            if let info = activeTouches.removeValue(forKey: id), let n = info.note {
                release(n)
            }
        }
    }
}
