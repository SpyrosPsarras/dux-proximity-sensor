import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "rule.js" as Rule

StyledRect {
    id: group

    required property var path
    required property var editor

    // Loader.setSource turns JS arrays into Qt lists, so take a real array and read the node from the editor's rule.
    // The fallback covers the moment between an edit and the Repeater rebuilding a removed item.
    readonly property var where: Array.from(path)
    readonly property var node: Rule.nodeAt(editor.rule, where) ?? Rule.group("any")
    readonly property bool isRoot: where.length === 0
    readonly property bool empty: node.items.length === 0
    readonly property bool met: editor.met(node)
    readonly property var needs: ["all", "any", "one"]
    readonly property string addDeviceText: editor.tr("Add a device")
    readonly property string addWifiText: editor.tr("Add a Wi-Fi network")

    height: content.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: where.length % 2 ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
    border.width: 2
    border.color: Rule.isComplete(node) ? (met ? Theme.primary : Theme.error) : Theme.outlineVariant

    component StateChip: StyledRect {
        id: chip
        property bool on: false
        property bool known: true
        property string label: ""
        width: chipText.implicitWidth + Theme.spacingM * 2
        height: chipText.implicitHeight + Theme.spacingXS * 2
        radius: height / 2
        color: !known ? Theme.surfaceContainer : on ? Theme.primaryContainer : Theme.errorContainer
        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: !chip.known ? Theme.surfaceVariantText : chip.on ? Theme.onPrimaryContainer : Theme.onErrorContainer
        }
    }

    component DeviceRow: StyledRect {
        id: row
        required property var path
        required property var editor
        readonly property var node: Rule.nodeAt(editor.rule, path) ?? Rule.device("", "")
        readonly property bool near: editor.nearNow(node)
        readonly property bool isWifi: node.kind === "wifi"
        readonly property bool bySignal: node.check === "signal"
        readonly property real strongest: editor.strongest(node)
        readonly property var checks: ["connected", "signal"]
        readonly property var checkLabels: [editor.tr("While connected"), editor.tr("By signal strength")]

        height: rowContent.implicitHeight + Theme.spacingS * 2
        radius: Theme.cornerRadiusS
        color: Theme.surfaceContainer

        function update(changes) {
            editor.edit(path, Object.assign({}, node, changes));
        }

        Column {
            id: rowContent
            x: Theme.spacingS
            y: Theme.spacingS
            width: parent.width - Theme.spacingS * 2
            spacing: Theme.spacingS

            Item {
                width: parent.width
                height: Math.max(nameColumn.implicitHeight, rowActions.height)

                DIcon {
                    id: deviceIcon
                    name: row.editor.iconFor(row.node)
                    size: Theme.iconSize
                    color: row.near ? Theme.primary : Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    id: nameColumn
                    anchors.left: deviceIcon.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: rowActions.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        width: parent.width
                        text: row.node.name
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        text: {
                            if (row.isWifi)
                                return row.near ? row.editor.tr("Connected to this Wi-Fi network") : row.editor.tr("Not connected to this Wi-Fi network");
                            if (!row.bySignal)
                                return row.near ? row.editor.tr("Connected") : row.editor.tr("Not connected");
                            if (row.strongest === -Infinity)
                                return row.editor.tr("No reading in the last %1 s").arg(row.editor.live?.signalTimeout ?? 20);
                            return row.editor.tr("Strongest recent reading %1 dBm. Needs %2 dBm or stronger.").arg(row.strongest).arg(row.node.minSignal);
                        }
                    }
                }

                Row {
                    id: rowActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    StateChip {
                        anchors.verticalCenter: parent.verticalCenter
                        on: row.near
                        known: !!row.editor.live
                        label: row.near ? row.editor.tr("Nearby") : row.editor.tr("Away")
                    }

                    DActionButton {
                        iconName: "close"
                        tooltipText: row.isWifi ? row.editor.tr("Remove this network") : row.editor.tr("Remove this device")
                        onClicked: row.editor.edit(row.path, null)
                    }
                }
            }

            Item {
                width: parent.width
                height: checkDropdown.height
                visible: !row.isWifi

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.editor.tr("Counts as nearby")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                DDropdown {
                    id: checkDropdown
                    anchors.right: parent.right
                    dropdownWidth: 220
                    options: row.checkLabels
                    currentValue: row.checkLabels[row.checks.indexOf(row.node.check)] ?? ""
                    onValueChanged: value => row.update({
                            "check": row.checks[row.checkLabels.indexOf(value)]
                        })
                }
            }

            DSlider {
                width: parent.width
                visible: row.bySignal
                minimum: -100
                maximum: -30
                value: row.node.minSignal ?? -70
                unit: "dBm"
                startIcon: "signal_cellular_1_bar"
                endIcon: "signal_cellular_4_bar"
                // The tree is rebuilt on every save, so a save mid-drag would destroy this slider.
                onSliderDragFinished: finalValue => row.update({
                        "minSignal": finalValue
                    })
            }

            StyledText {
                width: parent.width
                visible: row.bySignal
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                text: row.editor.tr("Move right to require the device closer to the computer. The device has to send Bluetooth LE advertisements to be seen.")
            }
        }
    }

    Column {
        id: content
        x: Theme.spacingM
        y: Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingS

        Item {
            width: parent.width
            height: Math.max(title.implicitHeight, headerActions.height)

            StyledText {
                id: title
                anchors.left: parent.left
                anchors.right: headerActions.left
                anchors.verticalCenter: parent.verticalCenter
                text: group.isRoot ? group.editor.tr("Stay unlocked while…") : group.editor.tr("This group counts as nearby when…")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
            }

            Row {
                id: headerActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StateChip {
                    anchors.verticalCenter: parent.verticalCenter
                    known: !!group.editor.live && Rule.isComplete(group.node)
                    on: group.met
                    label: !known ? group.editor.tr("Not checked") : group.met ? group.editor.tr("Met") : group.editor.tr("Not met")
                }

                DActionButton {
                    visible: !group.isRoot
                    iconName: "delete"
                    tooltipText: group.editor.tr("Remove this group")
                    onClicked: group.editor.edit(group.where, null)
                }
            }
        }

        DButtonGroup {
            width: parent.width
            fillWidth: true
            maximumWidth: width
            arrowKeysSelect: false
            checkEnabled: false
            model: [group.editor.tr("All of these"), group.editor.tr("Any of these"), group.editor.tr("Exactly one of these")]
            currentIndex: group.needs.indexOf(group.node.need)
            onSelectionChanged: (index, selected) => {
                if (selected && group.needs[index] !== group.node.need)
                    group.editor.edit(group.where, Object.assign({}, group.node, {
                        "need": group.needs[index]
                    }));
            }
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: {
                if (group.empty)
                    return group.editor.tr("Add a device, a Wi-Fi network or a group. An empty group pauses the whole rule.");
                if (group.node.need === "all")
                    return group.editor.tr("Every item below must count as nearby.");
                if (group.node.need === "one")
                    return group.editor.tr("Exactly one item below must count as nearby. If more than one does, this counts as away.");
                return group.editor.tr("At least one item below must count as nearby.");
            }
        }

        Repeater {
            model: group.node.items

            delegate: Loader {
                required property var modelData
                required property int index
                readonly property var childPath: group.where.concat([index])

                width: content.width
                Component.onCompleted: {
                    if (modelData.kind === "group")
                        setSource(Qt.resolvedUrl("RuleGroup.qml"), {
                            "path": childPath,
                            "editor": group.editor
                        });
                    else
                        sourceComponent = deviceRowComponent;
                }

                Component {
                    id: deviceRowComponent
                    DeviceRow {
                        path: childPath
                        editor: group.editor
                    }
                }
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingS

            DDropdown {
                dropdownWidth: 260
                options: group.editor.deviceLabels
                emptyText: group.editor.tr("No Bluetooth devices found")
                currentValue: group.addDeviceText
                onValueChanged: value => {
                    group.editor.addDevice(group.where, value);
                    currentValue = group.addDeviceText;
                }
            }

            DDropdown {
                dropdownWidth: 260
                options: group.editor.wifiNames
                emptyText: group.editor.tr("No saved Wi-Fi networks")
                currentValue: group.addWifiText
                onValueChanged: value => {
                    group.editor.addWifi(group.where, value);
                    currentValue = group.addWifiText;
                }
            }

            DButton {
                text: group.editor.tr("Add a group")
                iconName: "add"
                onClicked: group.editor.addGroup(group.where)
            }
        }
    }
}
