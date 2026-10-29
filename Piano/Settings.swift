import CoreAudioKit
import UIKit

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let internalSound = "internalSound"
        static let midiChannel = "midiChannel"
    }

    private init() {
        defaults.register(defaults: [Key.internalSound: true, Key.midiChannel: 0])
        internalSound = defaults.bool(forKey: Key.internalSound)
        midiChannel = defaults.integer(forKey: Key.midiChannel)
    }

    /// Whether the built-in synth sounds. Turn off when using the app only as a MIDI controller.
    var internalSound: Bool {
        didSet { defaults.set(internalSound, forKey: Key.internalSound) }
    }

    /// MIDI channel, 0...15 (shown to the user as 1...16).
    var midiChannel: Int {
        didSet { defaults.set(midiChannel, forKey: Key.midiChannel) }
    }
}

final class SettingsViewController: UITableViewController {
    private let soundSwitch = UISwitch()
    private let channelStepper = UIStepper()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))

        soundSwitch.isOn = Settings.shared.internalSound
        soundSwitch.addTarget(self, action: #selector(soundChanged), for: .valueChanged)

        channelStepper.minimumValue = 1
        channelStepper.maximumValue = 16
        channelStepper.value = Double(Settings.shared.midiChannel + 1)
        channelStepper.addTarget(self, action: #selector(channelChanged), for: .valueChanged)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func soundChanged() {
        Settings.shared.internalSound = soundSwitch.isOn
    }

    @objc private func channelChanged() {
        Settings.shared.midiChannel = Int(channelStepper.value) - 1
        tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Sound" : "MIDI Output"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return "Notes are sent to other apps via the \"Piano\" MIDI source, to a Mac over USB "
            + "(Audio MIDI Setup > iOS device) or Network MIDI, and to connected Bluetooth MIDI devices."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        switch (indexPath.section, indexPath.row) {
        case (0, _):
            cell.textLabel?.text = "Internal Sound"
            cell.accessoryView = soundSwitch
        case (1, 0):
            cell.textLabel?.text = "Channel"
            cell.detailTextLabel?.text = "\(Settings.shared.midiChannel + 1)"
            cell.accessoryView = channelStepper
        default:
            cell.textLabel?.text = "Bluetooth MIDI"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath == IndexPath(row: 1, section: 1) {
            // Advertises this device as a Bluetooth MIDI peripheral while shown.
            navigationController?.pushViewController(CABTMIDILocalPeripheralViewController(), animated: true)
        }
    }
}
