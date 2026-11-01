import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "rule.js" as Rule

PluginSettings {
    id: root
    pluginId: "proximityLock"

    property var rule: Rule.group("any")
    readonly property var live: PluginService.globalVars[pluginId]?.live ?? null
    readonly property var knownDevices: {
        const named = (BluetoothService.devices?.values ?? []).filter(d => d.address && d.name && d.name.replace(/-/g, ":").toUpperCase() !== d.address.toUpperCase());
        return named.sort((a, b) => (b.paired - a.paired) || a.name.localeCompare(b.name));
    }
    readonly property var deviceLabels: knownDevices.map(deviceLabel)

    function tr(text) {
        return I18n.trFor(pluginId, text);
    }

    function deviceLabel(d) {
        return d.paired ? `${d.name} · ${d.address}` : `${d.name} · ${d.address} · ${tr("not paired")}`;
    }

    function loadRule() {
        rule = loadValue("rule", null) ?? Rule.group("any");
    }

    function edit(path, node) {
        rule = Rule.replaceAt(rule, path, node);
        saveValue("rule", rule);
    }

    function addDevice(path, label) {
        const d = knownDevices[deviceLabels.indexOf(label)];
        if (!d)
            return;
        const group = Rule.nodeAt(rule, path);
        if (group.items.some(item => item.kind === "device" && item.address === d.address.toUpperCase()))
            return;
        edit(path, Object.assign({}, group, {
            "items": group.items.concat([Rule.device(d.address, d.name)])
        }));
    }

    function addGroup(path) {
        const group = Rule.nodeAt(rule, path);
        edit(path, Object.assign({}, group, {
            "items": group.items.concat([Rule.group("any")])
        }));
    }

    function nearNow(node) {
        return !!live && (node.check === "signal" ? strongest(node) >= node.minSignal : live.connected[node.address] === true);
    }

    function strongest(node) {
        return live?.strongest?.[node.address] ?? -Infinity;
    }

    function met(node) {
        return Rule.isComplete(node) && Rule.isMet(node, nearNow);
    }

    function iconFor(address) {
        const d = (BluetoothService.devices?.values ?? []).find(x => (x.address || "").toUpperCase() === address);
        return d ? BluetoothService.getDeviceIcon(d) : "bluetooth";
    }

    onPluginServiceChanged: loadRule()
    Component.onCompleted: loadRule()

    StyledText {
        width: parent.width
        text: root.tr("Lock the screen when you walk away")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: root.tr("Build a rule from your Bluetooth devices. While the rule is met you count as nearby and the screen stays unlocked. When it stops being met, the screen locks. It never unlocks the screen.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        id: banner
        readonly property string state: {
            if (!BluetoothService.enabled)
                return "off";
            if (!root.live)
                return "stopped";
            if (!root.live.ready)
                return "incomplete";
            if (root.live.met)
                return "near";
            return root.live.armed ? "locking" : "waiting";
        }
        readonly property int secondsLeft: root.live?.secondsLeft ?? 0

        width: parent.width
        height: bannerRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: state === "near" ? Theme.primaryContainer : state === "locking" ? Theme.errorContainer : Theme.surfaceContainerHigh

        Row {
            id: bannerRow
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingM

            DIcon {
                name: ({
                        "off": "bluetooth_disabled",
                        "stopped": "pause_circle",
                        "incomplete": "edit",
                        "near": "lock_open",
                        "locking": "lock_clock",
                        "waiting": "hourglass_empty"
                    })[banner.state]
                size: Theme.iconSize
                color: banner.state === "near" ? Theme.onPrimaryContainer : banner.state === "locking" ? Theme.onErrorContainer : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - Theme.iconSize - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
                color: banner.state === "near" ? Theme.onPrimaryContainer : banner.state === "locking" ? Theme.onErrorContainer : Theme.surfaceText
                text: ({
                        "off": root.tr("Bluetooth is off. Every device counts as away."),
                        "stopped": root.tr("The plugin isn't running. Turn it on to see live status."),
                        "incomplete": root.tr("Add at least one device. A group with nothing in it pauses the rule."),
                        "near": root.tr("You count as nearby. The screen stays unlocked."),
                        "locking": root.tr("You count as away. Locking in %1 s.").arg(banner.secondsLeft),
                        "waiting": root.tr("You count as away. The screen won't lock until the rule has been met once.")
                    })[banner.state]
            }
        }
    }

    RuleGroup {
        width: parent.width
        path: []
        editor: root
    }

    SliderSetting {
        settingKey: "lockDelay"
        label: root.tr("Wait before locking")
        description: root.tr("How long the rule must stay unmet before the screen locks.")
        defaultValue: 5
        minimum: 0
        maximum: 60
        unit: "s"
    }

    SliderSetting {
        settingKey: "signalTimeout"
        label: root.tr("Signal timeout")
        description: root.tr("A device checked by signal strength counts as away after this long without a strong enough reading. Devices can go several seconds between readings, so keep this above 10 s.")
        defaultValue: 20
        minimum: 5
        maximum: 120
        unit: "s"
    }
}
