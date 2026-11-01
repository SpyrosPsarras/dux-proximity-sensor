import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "rule.js" as Rule

PluginComponent {
    id: root

    readonly property var rule: pluginData.rule ?? null
    readonly property string ruleContent: JSON.stringify(rule)
    readonly property int lockDelay: pluginData.lockDelay ?? 5
    readonly property int signalTimeout: pluginData.signalTimeout ?? 20
    readonly property bool ready: Rule.isComplete(rule)
    readonly property var signalAddresses: ready ? Rule.devices(rule).filter(d => d.check === "signal").map(d => d.address) : []
    readonly property bool needsScan: signalAddresses.length > 0
    readonly property string adapterPath: BluetoothService.adapter?.dbusPath ?? ""

    property var samples: ({})
    property var subscriptions: null
    property var scan: null
    property string publishedStatus: ""
    property bool armed: false
    property real awaySince: 0
    property bool met: false

    // Editing the rule must not lock the screen: wait until the new rule is met once.
    onRuleContentChanged: {
        armed = false;
        awaySince = 0;
        samples = {};
        resync();
    }
    onMetChanged: console.info("ProximityLock: rule", met ? "met" : "not met")
    onAdapterPathChanged: {
        samples = {};
        resync();
    }

    function connectedMap() {
        const map = {};
        for (const d of BluetoothService.devices?.values ?? []) {
            if (d.connected)
                map[(d.address || "").toUpperCase()] = true;
        }
        return map;
    }

    function tick() {
        const now = Date.now();
        const timeoutMs = signalTimeout * 1000;
        samples = Rule.prune(samples, now, timeoutMs);
        const live = {
            connected: connectedMap(),
            samples: samples,
            // The SSID goes stale when the backend drops, and a hotspot can report its own name: count both as away.
            wifi: DMSService.isConnected && NetworkService.wifiConnected && !NetworkService.hotspotEnabled ? NetworkService.currentWifiSSID : ""
        };
        met = ready && Rule.isMet(rule, node => Rule.isNear(node, live, now, timeoutMs));

        if (!ready) {
            armed = false;
            awaySince = 0;
        } else if (met) {
            armed = true;
            awaySince = 0;
        } else if (armed) {
            if (!awaySince)
                awaySince = now;
            if (now - awaySince >= lockDelay * 1000) {
                armed = false;
                awaySince = 0;
                if (!IdleService.isShellLocked) {
                    console.info("ProximityLock: rule not met for", lockDelay, "s, locking");
                    IdleService.lockRequested();
                }
            }
        }

        const strongest = {};
        for (const address in samples)
            strongest[address] = Rule.strongestSignal(address, live, now, timeoutMs);
        const status = {
            "connected": live.connected,
            "wifi": live.wifi,
            "strongest": strongest,
            "ready": ready,
            "met": met,
            "armed": armed,
            "secondsLeft": awaySince ? Math.max(0, Math.ceil((awaySince + lockDelay * 1000 - now) / 1000)) : 0,
            "signalTimeout": signalTimeout
        };
        const content = JSON.stringify(status);
        if (content !== publishedStatus) {
            publishedStatus = content;
            PluginService.setGlobalVar(pluginId, "live", status);
        }
    }

    function handleBluezSignal(data) {
        const body = data.body || [];
        if (body[0] !== "org.bluez.Device1" || body[1]?.RSSI === undefined)
            return;
        const match = /dev_([0-9A-F_]{17})$/.exec(data.path || "");
        if (!match)
            return;
        const address = match[1].replace(/_/g, ":");
        if (!signalAddresses.includes(address))
            return;
        const reading = [Date.now(), Number(body[1].RSSI)];
        const next = Object.assign({}, samples);
        next[address] = (samples[address] || []).concat([reading]);
        samples = next;
    }

    // The filter makes BlueZ report RSSI for every advertisement, not only 8 dBm jumps (src/adapter.c, filtered_discovery).
    // Filter and discovery belong to the shell backend's bus connection, so they stay separate from the Control Center scan.
    function startScan() {
        if (!needsScan || !adapterPath || !DMSService.isConnected || !DMSService.capabilities.includes("dbus"))
            return;
        if (!scan)
            scan = { "path": adapterPath, "started": false, "pending": false, "cancelled": false };
        const session = scan;
        if (session.pending)
            return;
        const dms = DMSService;
        const path = session.path;
        // Late replies must use only captured JS state: the QML object may already be destroyed.
        const call = (method, args, callback) => dms.dbusCall("system", "org.bluez", path, "org.bluez.Adapter1", method, args, callback);
        session.pending = true;
        // shortcut: setting this filter can make another backend client's discovery LE-only, coordinate shared discovery if coexistence is needed.
        call("SetDiscoveryFilter", [
            {
                "Transport": "le",
                "DuplicateData": true
            }
        ], filterResponse => {
            if (session.cancelled) {
                session.pending = false;
                call("SetDiscoveryFilter", [{}], () => {});
                return;
            }
            if (filterResponse.error)
                console.warn("ProximityLock: SetDiscoveryFilter failed:", filterResponse.error);
            call("StartDiscovery", [], response => {
                session.pending = false;
                if (session.cancelled) {
                    call("SetDiscoveryFilter", [{}], () => {});
                    if (!response.error)
                        call("StopDiscovery", [], () => {});
                    return;
                }
                if (response.error) {
                    if (!/in progress/i.test(response.error))
                        console.warn("ProximityLock: StartDiscovery failed:", response.error);
                    return;
                }
                session.started = true;
            });
        });
    }

    function stopScan() {
        const session = scan;
        scan = null;
        if (!session)
            return;
        session.cancelled = true;
        if (DMSService.isConnected) {
            DMSService.dbusCall("system", "org.bluez", session.path, "org.bluez.Adapter1", "SetDiscoveryFilter", [{}], () => {});
            if (session.started)
                DMSService.dbusCall("system", "org.bluez", session.path, "org.bluez.Adapter1", "StopDiscovery", [], () => {});
        }
    }

    function unsubscribe() {
        if (!subscriptions)
            return;
        subscriptions.cancelled = true;
        for (const id of subscriptions.ids)
            DMSService.dbusUnsubscribe(id);
        subscriptions = null;
    }

    function resync() {
        unsubscribe();
        if (scan && (scan.path !== adapterPath || !needsScan))
            stopScan();
        if (!DMSService.isConnected || !DMSService.capabilities.includes("dbus") || !adapterPath || !needsScan)
            return;
        const dms = DMSService;
        const batch = { "cancelled": false, "ids": [] };
        subscriptions = batch;
        for (const address of new Set(signalAddresses)) {
            const path = adapterPath + "/dev_" + address.replace(/:/g, "_");
            dms.dbusSubscribe("system", "org.bluez", path, "org.freedesktop.DBus.Properties", "PropertiesChanged", response => {
                if (response.error) {
                    console.warn("ProximityLock: subscribe failed:", response.error);
                    return;
                }
                if (batch.cancelled) {
                    dms.dbusUnsubscribe(response.result.subscriptionId);
                    return;
                }
                batch.ids.push(response.result.subscriptionId);
            });
        }
        startScan();
    }

    Connections {
        target: DMSService
        function onCapabilitiesReceived() {
            root.resync();
        }
        function onDbusSignalReceived(subscriptionId, data) {
            if (root.subscriptions?.ids.includes(subscriptionId))
                root.handleBluezSignal(data);
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    // Discovery ends when the adapter powers off or bluetoothd restarts; asking again is a no-op while it runs.
    Timer {
        interval: 30000
        running: root.needsScan && !!root.adapterPath
        repeat: true
        onTriggered: root.startScan()
    }

    Component.onCompleted: {
        if (DMSService.subscribeConnected)
            resync();
    }

    Component.onDestruction: {
        unsubscribe();
        stopScan();
        PluginService.setGlobalVar(pluginId, "live", null);
    }
}
