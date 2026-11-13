// Squat — un petit gars qui fait des squats dans la barre de menus.
// Plus le processeur travaille, plus la barre est chargée et plus les répétitions sont lentes.
import AppKit
import Darwin

// MARK: - Mesure de la charge CPU

final class CPUMonitor {
    private var previous: host_cpu_load_info?

    /// Charge globale entre 0 et 1 depuis le dernier appel.
    func sample() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { previous = info }
        guard let prev = previous else { return 0 }

        func delta(_ i: Int32) -> Double {
            let now = tick(info, i), before = tick(prev, i)
            return Double(now &- before)
        }
        let user = delta(CPU_STATE_USER), system = delta(CPU_STATE_SYSTEM)
        let nice = delta(CPU_STATE_NICE), idle = delta(CPU_STATE_IDLE)
        let total = user + system + nice + idle
        return total > 0 ? (user + system + nice) / total : 0
    }

    private func tick(_ info: host_cpu_load_info, _ i: Int32) -> UInt32 {
        switch i {
        case CPU_STATE_USER: return info.cpu_ticks.0
        case CPU_STATE_SYSTEM: return info.cpu_ticks.1
        case CPU_STATE_IDLE: return info.cpu_ticks.2
        default: return info.cpu_ticks.3
        }
    }
}

// MARK: - Niveaux de charge

struct Level {
    let plates: [Int]       // hauteur (en pixels) de chaque disque, de l'intérieur vers l'extérieur
    let period: Double      // durée d'une répétition (s)
    let amplitude: CGFloat  // 0…1 de l'amplitude complète
    let strain: Bool        // tremble pendant la poussée
}

let levels: [Level] = [
    Level(plates: [],               period: 0.8, amplitude: 1.0,  strain: false), // au repos : barre vide, reps rapides
    Level(plates: [6],              period: 0.9, amplitude: 1.0,  strain: false),
    Level(plates: [8],              period: 1.2, amplitude: 1.0,  strain: false),
    Level(plates: [8, 8],           period: 1.6, amplitude: 1.0,  strain: false),
    Level(plates: [8, 8, 8],        period: 2.2, amplitude: 1.0,  strain: true),
    Level(plates: [8, 8, 8, 8],    period: 3.2, amplitude: 1.0,  strain: true),
]

/// Seuils (charge CPU lissée) pour passer au niveau supérieur.
let thresholds: [Double] = [0.08, 0.25, 0.45, 0.65, 0.85]

func levelIndex(for load: Double) -> Int {
    thresholds.lastIndex(where: { load >= $0 }).map { $0 + 1 } ?? 0
}

// MARK: - Dessin (vue de face, yeux à hauteur de barre)

// Tout est dessiné sur une grille de pixels (1 pixel = 1 point), ligne 0 en haut, style 8-bit.
let cols = 52, rows = 18
let canvas = CGSize(width: cols, height: rows)
let barRowHigh = 4, barRowLow = 9  // ligne de la barre : debout / en bas du squat

// Encres de la grille : 0 = vide, 1 = corps et barre (blanc ou noir selon la barre de menus),
// 2 = justaucorps rouge, 3 = disques noirs
let singletRed = NSColor(srgbRed: 0.86, green: 0.11, blue: 0.14, alpha: 1)
let plateBlack = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)

struct PixelGrid {
    var px = [[UInt8]](repeating: [UInt8](repeating: 0, count: cols), count: rows)
    subscript(c: Int, r: Int) -> UInt8 {
        get { (0..<cols).contains(c) && (0..<rows).contains(r) ? px[r][c] : 0 }
        set { if (0..<cols).contains(c) && (0..<rows).contains(r) { px[r][c] = newValue } }
    }
    /// Remplit un rectangle, et son symétrique de l'autre côté du corps.
    mutating func fill(_ c0: Int, _ c1: Int, _ r0: Int, _ r1: Int, mirrored: Bool = true, value: UInt8 = 1) {
        for r in r0...r1 { for c in c0...c1 {
            self[c, r] = value
            if mirrored { self[cols - 1 - c, r] = value }
        } }
    }
    /// Trait épais de 2 pixels (bras), et son symétrique.
    mutating func line(_ a: CGPoint, _ b: CGPoint, value: UInt8 = 1, redUntil: CGFloat = 0) {
        let steps = Int(hypot(b.x - a.x, b.y - a.y) * 4) + 1
        for i in 0...steps {
            let k = CGFloat(i) / CGFloat(steps)
            let c = Int((a.x + (b.x - a.x) * k).rounded(.down)), r = Int((a.y + (b.y - a.y) * k).rounded(.down))
            fill(c, c + 1, r, r + 1, value: k < redUntil ? 2 : value)
        }
    }
}

/// `t` : 0 = squat en bas, 1 = debout. `jitter` : 1 = la barre s'affaisse d'un pixel (effort).
func drawFrame(level: Level, t: CGFloat, jitter: CGFloat, ink: NSColor) {
    var g = PixelGrid()
    let bar = min(barRowLow, Int((CGFloat(barRowLow) - CGFloat(barRowLow - barRowHigh) * t).rounded()) + Int(jitter))

    // Tête au-dessus de la barre (barre posée sur les trapèzes), deux yeux
    g.fill(24, 25, bar - 4, bar - 4)
    g.fill(23, 25, bar - 3, bar - 1)
    g.fill(24, 24, bar - 2, bar - 2, value: 0)
    // Épaules nues, puis justaucorps rouge du torse jusqu'au bassin
    g.fill(21, 21, bar + 1, bar + 1)
    g.fill(22, 25, bar + 1, bar + 1, value: 2)
    g.fill(22, 25, bar + 2, bar + 4, value: 2)
    g.fill(22, 25, bar + 5, bar + 5, value: 2)
    let hipRow = bar + 6
    g.fill(22, 25, hipRow, hipRow, value: 2)

    // Bras : poings sur la barre, coudes vers le bas
    g.fill(17, 18, bar - 1, bar + 1)
    g.fill(18, 19, bar + 1, bar + 3)
    g.fill(20, 20, bar + 1, bar + 1)

    // Jambes : cinématique inverse hanche → genou → cheville, genoux qui s'ouvrent vers l'extérieur
    let hip = CGPoint(x: 22.5, y: CGFloat(hipRow)), ankle = CGPoint(x: 21.5, y: 15.5)
    let legLength: CGFloat = 5.55
    let dx = ankle.x - hip.x, dy = ankle.y - hip.y
    let d = max(0.5, min(hypot(dx, dy), legLength - 0.01))
    let h = sqrt(max(0, legLength * legLength / 4 - d * d / 4))
    var n = CGPoint(x: -dy / d, y: dx / d)
    if n.x > 0 { n = CGPoint(x: -n.x, y: -n.y) }
    let knee = CGPoint(x: (hip.x + ankle.x) / 2 + n.x * h, y: (hip.y + ankle.y) / 2 + n.y * h)
    // Short rouge : toute la cuisse, et le haut du tibia quand il est debout (≈ 3 px plus bas qu'avant).
    // En bas du squat, le tibia reste nu pour que le short ne « coule » pas le long de la jambe.
    // Chaque segment est tracé d'un seul trait pour éviter les liserés.
    let depth = CGFloat(bar - barRowHigh) / CGFloat(barRowLow - barRowHigh) // 0 debout, 1 en bas
    g.line(knee, ankle, redUntil: 0.55 * (1 - depth))
    g.line(hip, knee, redUntil: 1.01)
    // Pieds au sol, légèrement ouverts
    g.fill(18, 22, 17, 17)

    // Barre, colliers, disques (2 px de large, 1 px d'écart)
    g.fill(0, 25, bar, bar)
    g.fill(12, 12, bar - 1, bar + 1)
    for (i, height) in level.plates.enumerated() {
        let c = 9 - 3 * i
        g.fill(c, c + 1, bar - height / 2, bar + height / 2 - 1, value: 3)
        // Liseré haut et bas dans la couleur du corps : les disques noirs restent visibles sur barre sombre
        g.fill(c, c + 1, bar - height / 2, bar - height / 2)
        g.fill(c, c + 1, bar + height / 2 - 1, bar + height / 2 - 1)
    }

    let palette: [UInt8: NSColor] = [1: ink, 2: singletRed, 3: plateBlack]
    NSGraphicsContext.current?.shouldAntialias = false
    for r in 0..<rows { for c in 0..<cols where g[c, r] != 0 {
        palette[g[c, r]]!.setFill()
        NSRect(x: c, y: rows - 1 - r, width: 1, height: 1).fill()
    } }
}

/// `dark` : barre de menus sombre → corps et barre en blanc, sinon en noir.
func makeImage(level: Level, t: CGFloat, jitter: CGFloat, dark: Bool) -> NSImage {
    NSImage(size: canvas, flipped: false) { _ in
        drawFrame(level: level, t: t, jitter: jitter, ink: dark ? .white : .black)
        return true
    }
}

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: canvas.width + 4)
    private let monitor = CPUMonitor()
    private var smoothedLoad = 0.0
    private var currentLevel = 0
    private var phase = 0.0
    private var lastTick = Date()
    private let loadItem = NSMenuItem(title: "CPU : —", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.addItem(loadItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        _ = monitor.sample()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateLoad() }
        let anim = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.animate() }
        RunLoop.main.add(anim, forMode: .common) // continue à tourner pendant que le menu est ouvert
        animate()
    }

    private func updateLoad() {
        let raw = monitor.sample()
        smoothedLoad = smoothedLoad * 0.6 + raw * 0.4

        // Hystérésis : on ne redescend que si la charge passe nettement sous le seuil
        let target = levelIndex(for: smoothedLoad)
        if target > currentLevel || levelIndex(for: smoothedLoad + 0.05) < currentLevel {
            currentLevel = target
        }
        let plates = levels[currentLevel].plates.count
        loadItem.title = String(format: "CPU : %.0f %%  ·  %d disque%@ par côté",
                                smoothedLoad * 100, plates, plates > 1 ? "s" : "")
    }

    private func animate() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let level = levels[currentLevel]
        // Le cycle commence par une pause debout, jambes tendues (20 %), ajoutée en plus de la durée
        // du mouvement : la descente et la remontée gardent leur vitesse.
        let hold = 0.2
        phase = (phase + dt * (1 - hold) / level.period).truncatingRemainder(dividingBy: 1)

        // Puis descente rapide, poussée plus lente : plus réaliste sous lourde charge
        let down = hold + 0.35 * (1 - hold)
        let raw: Double = phase < hold ? 1
            : phase < down
            ? 0.5 + 0.5 * cos(.pi * (phase - hold) / (down - hold))  // 1 → 0
            : 0.5 - 0.5 * cos(.pi * (phase - down) / (1 - down))     // 0 → 1
        let t = 1 - CGFloat(level.amplitude) * CGFloat(1 - raw)
        let pushing = phase >= down && phase < 0.95
        let jitter: CGFloat = level.strain && pushing ? (Double.random(in: 0..<1) < 0.25 ? 1 : 0) : 0

        guard let button = statusItem.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.image = makeImage(level: level, t: t, jitter: jitter, dark: dark)
    }
}

// MARK: - Point d'entrée

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--preview" {
    // Planche d'aperçu : une ligne par niveau ; trois positions sur barre claire puis sur barre sombre ; ×8
    let scale: CGFloat = 8
    let cols: [(t: Double, dark: Bool)] = [0, 0.25, 0.5, 0.75, 1].map { ($0, false) } + [0, 0.25, 0.5, 0.75, 1].map { ($0, true) }
    let cell = CGSize(width: (canvas.width + 6) * scale, height: (canvas.height + 4) * scale)
    let size = NSSize(width: cell.width * CGFloat(cols.count), height: cell.height * CGFloat(levels.count))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(white: 0.93, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
    NSColor(white: 0.16, alpha: 1).setFill()
    NSRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height).fill()
    for (row, level) in levels.enumerated() {
        for (col, cfg) in cols.enumerated() {
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(col) * cell.width + 3 * scale,
                            y: size.height - CGFloat(row + 1) * cell.height + 2 * scale)
            ctx.scaleBy(x: scale, y: scale)
            drawFrame(level: level, t: CGFloat(cfg.t) * CGFloat(level.amplitude) + (1 - CGFloat(level.amplitude)),
                      jitter: 0, ink: cfg.dark ? .white : .black)
            ctx.restoreGState()
        }
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // pas d'icône dans le Dock
app.run()
