import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    static let synth = PianoSynth()
    static let midi = MIDIOutput()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AppDelegate.synth.start()
        _ = AppDelegate.midi
        application.isIdleTimerDisabled = true
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .landscape
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = PianoViewController(synth: AppDelegate.synth, midi: AppDelegate.midi)
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AppDelegate.synth.resume()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppDelegate.synth.suspend()
    }
}

final class PianoViewController: UIViewController {
    private static let barHeight: CGFloat = 28

    private let synth: PianoSynth
    private let midi: MIDIOutput
    private let keyboard = KeyboardView()
    private let bar = UIView()
    private let settingsButton = UIButton(type: .system)

    init(synth: PianoSynth, midi: MIDIOutput) {
        self.synth = synth
        self.midi = midi
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        keyboard.onNoteOn = { [synth, midi] note, velocity in
            let settings = Settings.shared
            if settings.internalSound { synth.noteOn(note, velocity: velocity) }
            midi.noteOn(note, velocity: velocity, channel: settings.midiChannel)
        }
        keyboard.onNoteOff = { [synth, midi] note in
            synth.noteOff(note)
            midi.noteOff(note, channel: Settings.shared.midiChannel)
        }
        view.addSubview(keyboard)

        bar.backgroundColor = UIColor(white: 0.12, alpha: 1)
        view.addSubview(bar)
        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.tintColor = UIColor(white: 0.75, alpha: 1)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        bar.addSubview(settingsButton)
    }

    @objc private func openSettings() {
        let nav = UINavigationController(rootViewController: SettingsViewController())
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let width = view.bounds.width - safe.left - safe.right
        let barHeight = PianoViewController.barHeight
        bar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: barHeight)
        settingsButton.frame = CGRect(x: view.bounds.width - safe.right - 44, y: 0, width: 44, height: barHeight)
        keyboard.frame = CGRect(x: safe.left, y: barHeight,
                                width: width,
                                height: view.bounds.height - barHeight)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool { true }
}
