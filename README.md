# Piano

Simple landscape-only iOS piano. Opens straight to the keyboard (two octaves
visible, 88 keys total); swipe horizontally to scroll the visible range.

- Touch-down plays immediately (UIKit touch handling, multi-touch).
- Dragging a held finger horizontally more than 14pt scrolls the keyboard; the held note keeps sounding until the finger lifts.
- Sound is a built-in additive synth rendered in an `AVAudioSourceNode`
  (5 ms preferred IO buffer), so no sample files are needed.
- MIDI controller: notes are sent via the virtual source "Piano", Network MIDI,
  USB to a Mac (Audio MIDI Setup > iOS device) and Bluetooth MIDI. The gear
  button opens settings (internal sound on/off, MIDI channel, Bluetooth MIDI).

## Build

```
curl -L -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
unzip -q xcodegen.zip
./xcodegen/bin/xcodegen generate
open Piano.xcodeproj
```

Set a signing team in Xcode and run on a device (the simulator has higher audio latency).
