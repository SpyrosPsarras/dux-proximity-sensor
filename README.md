<img src="assets/icon.svg" width="64" height="64" alt="">

# Proximity Lock

A [Dux Shell](https://github.com/duxlabs-dev/dux-shell) daemon plugin that locks the screen when your Bluetooth devices leave, or when you leave a Wi-Fi network. It never unlocks.

You build a rule from your devices and Wi-Fi networks in the plugin settings. While the rule is met you count as nearby. When it stops being met for the "Wait before locking" time, the shell locks the screen.

## Rules

A rule is a group. Each group holds devices, Wi-Fi networks and other groups, nested as deep as you like, and asks for one of:

| In the settings | Met when |
|---|---|
| All of these | every item is nearby |
| Any of these | at least one item is nearby |
| Exactly one of these | one item is nearby, no more |

Example: "All of these: Phone, and a group with Exactly one of these: Watch, Earbuds" stays unlocked while the phone is nearby with either the watch or the earbuds, but not both.

The settings page shows each device and group as Nearby or Away, live. An empty group pauses the whole rule.

The plugin only locks after it has seen the rule met. Starting the shell or editing the rule resets that state: the rule must be met once before it can lock again. Changing "Wait before locking" or "Signal timeout" does not reset that state or cancel a pending countdown.

## How a device counts as nearby

Each device uses one check:

- **While connected.** Nearby while BlueZ reports it connected. Costs nothing. Phones often drop an idle connection, so this suits devices that stay connected: keyboards, headphones, a watch paired to this computer.
- **By signal strength.** Nearby while a Bluetooth LE advertisement at or above the chosen dBm arrived within the "Signal timeout". The device must send LE advertisements to this computer. While any device uses this check, the plugin keeps a BlueZ LE discovery session open.

Phones that rotate their Bluetooth address show up under a new address unless they are bonded with this computer. Pick the device from the paired list when you can.

## Wi-Fi networks

A Wi-Fi network counts as nearby while this computer is connected to it, matched by its exact name (SSID). The list offers your saved networks and the one you're connected to.

Example: "Any of these: Home Wi-Fi, Phone (Bluetooth)" stays unlocked at home, and elsewhere only while the phone is connected.

A network name proves nothing on its own: anyone can run an access point with the same name. How much that matters depends on the network's security:

- **WPA2/WPA3-Personal:** an impostor needs the password. Anyone who knows it, such as guests or coworkers on a shared password, can imitate the network.
- **WPA2/WPA3-Enterprise:** an impostor is kept out only if the connection profile checks the server certificate and its domain. A name shared across many sites, such as eduroam, counts as nearby at every one of them.
- **Open:** no protection. Avoid adding open networks.

Wi-Fi counts as away while it reconnects, while this computer runs a hotspot, and while the shell's backend is restarting. If the network is what keeps the rule met, a drop longer than "Wait before locking" locks the screen.

## Requirements

- Dux Shell 2.0 or newer, with the `dbus` backend capability.
- For Wi-Fi networks, the shell's network service must be running.
- BlueZ. The signal check uses `org.bluez.Adapter1` discovery with a filter, so BlueZ reports RSSI for every advertisement instead of only changes of 8 dBm or more.

## Install for development

Dux Shell 2.0 still uses the old DankMaterialShell names internally: the `dms` command, the `~/.config/dms` folder and the `requires_dms` manifest key.

```sh
ln -s "$PWD" ~/.config/dms/plugins/proximityLock
dms ipc call plugins enable proximityLock
```

`dms ipc call plugins reload proximityLock` reloads `ProximityLock.qml` and the settings page. Changes to `RuleGroup.qml` need `dms restart`, because the shell keeps the loaded type.

## Tests

```sh
node --test tests/rule.test.mjs
```

`journalctl --user -f | grep ProximityLock` shows when the rule changes between met and not met, and each lock.
