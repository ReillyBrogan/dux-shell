import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modals.DLauncherV2
import qs.Modals.DLauncherV2.Components
import qs.Services
import qs.Widgets

// Hosts the launcher inside a compositor overview. The compositor-specific
// adapter supplies its state and performs the actions it requests.
Scope {
    id: overviewScope

    required property bool overviewOpen
    required property string activeOutput
    required property string launcherStyle
    required property string lastMode
    required property string layerNamespace
    // An overview that takes the seat leaves a mapped launcher modal without keys.
    property bool dismissModalOnOpen: false
    // An overview that stays up when a window is focused hides the launched app.
    property bool closeOnItemExecuted: false

    signal closeOverviewRequested
    signal focusLeftRequested
    signal focusRightRequested
    signal focusUpRequested
    signal focusDownRequested
    signal lastModeChosen(string mode)

    property bool searchActive: false
    property string searchActiveScreen: ""
    property bool isClosing: false
    property bool releaseKeyboard: false
    readonly property bool spotlightModalOpen: PopoutService.dankLauncherV2Modal?.spotlightOpen ?? false
    readonly property bool overlayActive: overviewOpen || searchActive

    function showSpotlight(screenName) {
        isClosing = false;
        releaseKeyboard = false;
        searchActive = true;
        searchActiveScreen = screenName;
    }

    function hideSpotlight() {
        if (!searchActive)
            return;
        isClosing = true;
    }

    function resetState() {
        searchActive = false;
        searchActiveScreen = "";
        isClosing = false;
        releaseKeyboard = false;
    }

    onOverviewOpenChanged: {
        if (overviewOpen) {
            if (dismissModalOnOpen && spotlightModalOpen)
                PopoutService.closeDankLauncherV2();
            resetState();
            return;
        }
        if (!searchActive) {
            resetState();
            return;
        }
        isClosing = true;
    }

    onActiveOutputChanged: {
        if (!overviewOpen || !searchActive || searchActiveScreen === "" || searchActiveScreen === activeOutput)
            return;
        hideSpotlight();
    }

    onSpotlightModalOpenChanged: {
        if (spotlightModalOpen && searchActive)
            hideSpotlight();
    }

    onIsClosingChanged: {
        if (!isClosing) {
            closeTimer.stop();
            return;
        }
        closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: Theme.expressiveDurations.fast
        onTriggered: overviewScope.resetState()
    }

    Loader {
        active: overlayActive || isClosing
        asynchronous: false
        sourceComponent: Variants {
            model: ShellLayout.realScreens

            PanelWindow {
                id: overlayWindow
                required property var modelData

                readonly property real dpr: CompositorService.getScreenScale(screen)
                readonly property bool isActiveScreen: screen.name === overviewScope.activeOutput
                readonly property bool shouldShowSpotlight: overviewScope.searchActive && screen.name === overviewScope.searchActiveScreen && !overviewScope.isClosing
                readonly property bool isSpotlightScreen: screen.name === overviewScope.searchActiveScreen
                readonly property bool overlayVisible: overviewScope.overviewOpen || overviewScope.isClosing
                property bool hasActivePopout: !!PopoutManager.currentPopoutsByScreen[screen.name]
                property bool hasActiveModal: !!ModalManager.currentModalsByScreen[screen.name]
                readonly property bool useSpotlightStyle: overviewScope.launcherStyle === "spotlight"
                readonly property var launcherContent: useSpotlightStyle ? spotlightLauncherLoader.item : fullLauncherLoader.item

                readonly property QtObject fakeParentModal: QtObject {
                    readonly property bool spotlightOpen: spotlightContainer.visible
                    readonly property bool isClosing: overviewScope.isClosing
                    readonly property real alignedX: spotlightContainer.x
                    readonly property real alignedY: spotlightContainer.y
                    readonly property real screenHeight: overlayWindow.screen?.height ?? 1080
                    readonly property real frameBottomRadius: spotlightContainer.bottomRadius
                    function hide() {
                        if (overviewScope.searchActive) {
                            overviewScope.hideSpotlight();
                            return;
                        }
                        overviewScope.closeOverviewRequested();
                    }
                }

                Connections {
                    target: PopoutManager
                    function onPopoutChanged() {
                        overlayWindow.hasActivePopout = !!PopoutManager.currentPopoutsByScreen[overlayWindow.screen.name];
                    }
                }

                Connections {
                    target: ModalManager
                    function onModalChanged() {
                        overlayWindow.hasActiveModal = !!ModalManager.currentModalsByScreen[overlayWindow.screen.name];
                    }
                }

                screen: modelData
                visible: overlayVisible
                color: "transparent"

                WlrLayershell.namespace: overviewScope.layerNamespace
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: {
                    if (PopoutManager.screenshotActive)
                        return WlrKeyboardFocus.None;
                    if (!overviewScope.overviewOpen)
                        return WlrKeyboardFocus.None;
                    if (!isActiveScreen)
                        return WlrKeyboardFocus.None;
                    if (overviewScope.releaseKeyboard)
                        return WlrKeyboardFocus.None;
                    if (hasActivePopout || hasActiveModal)
                        return WlrKeyboardFocus.None;
                    return WlrKeyboardFocus.Exclusive;
                }

                mask: Region {
                    item: overlayVisible && spotlightContainer.visible ? spotlightContainer : null
                }

                WindowBlur {
                    targetWindow: overlayWindow
                    surfaceColor: Theme.floatingWindowSurface
                    readonly property real s: Math.min(1, spotlightContainer.scale)
                    readonly property bool active: overlayWindow.shouldShowSpotlight && spotlightContainer.opacity > 0
                    blurX: spotlightContainer.x + spotlightContainer.width * (1 - s) * 0.5
                    blurY: spotlightContainer.y + spotlightContainer.height * (1 - s) * 0.5
                    blurWidth: active ? spotlightContainer.width * s : 0
                    blurHeight: active ? spotlightContainer.height * s : 0
                    blurRadius: spotlightContainer.cornerRadius
                    blurBottomRadius: spotlightContainer.bottomRadius
                }

                onShouldShowSpotlightChanged: {
                    if (shouldShowSpotlight) {
                        if (launcherContent?.controller) {
                            launcherContent.controller.searchMode = overviewScope.lastMode || "apps";
                            launcherContent.controller.performSearch();
                        }
                        return;
                    }
                    if (!isActiveScreen)
                        return;
                    Qt.callLater(() => keyboardFocusScope.forceActiveFocus());
                }

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                FocusScope {
                    id: keyboardFocusScope
                    anchors.fill: parent
                    focus: true

                    Keys.onPressed: event => {
                        if (overlayWindow.shouldShowSpotlight || overviewScope.isClosing)
                            return;
                        if ([Qt.Key_Escape, Qt.Key_Return].includes(event.key)) {
                            overviewScope.closeOverviewRequested();
                            event.accepted = true;
                            return;
                        }

                        if (event.key === Qt.Key_Left) {
                            overviewScope.focusLeftRequested();
                            event.accepted = true;
                            return;
                        }

                        if (event.key === Qt.Key_Right) {
                            overviewScope.focusRightRequested();
                            event.accepted = true;
                            return;
                        }

                        if (event.key === Qt.Key_Up) {
                            overviewScope.focusUpRequested();
                            event.accepted = true;
                            return;
                        }

                        if (event.key === Qt.Key_Down) {
                            overviewScope.focusDownRequested();
                            event.accepted = true;
                            return;
                        }

                        if (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier) || [Qt.Key_Delete, Qt.Key_Backspace].includes(event.key)) {
                            event.accepted = false;
                            return;
                        }

                        if (event.isAutoRepeat || !event.text)
                            return;
                        if (!overlayWindow.launcherContent?.searchField)
                            return;
                        const trimmedText = event.text.trim();
                        overlayWindow.launcherContent.searchField.text = trimmedText;
                        overlayWindow.launcherContent.controller.setSearchQuery(trimmedText);
                        overviewScope.showSpotlight(overlayWindow.screen.name);
                        Qt.callLater(() => overlayWindow.launcherContent.searchField.forceActiveFocus());
                        event.accepted = true;
                    }
                }

                Item {
                    id: spotlightContainer

                    readonly property string connectedEmergeSide: SettingsData.frameLauncherEmergeSide || "bottom"
                    readonly property real _centerY: overlayWindow.useSpotlightStyle ? LauncherMetrics.spotlightY(parent.height, 0, 0) : (parent.height - height) / 2
                    readonly property real _connectedRestY: {
                        if (!Theme.isConnectedEffect || !overlayWindow.screen)
                            return _centerY;
                        const inset = SettingsData.frameEdgeInsetForSide(overlayWindow.screen, connectedEmergeSide);
                        return connectedEmergeSide === "top" ? inset : parent.height - height - inset;
                    }
                    readonly property real _connectedCollapsedY: connectedEmergeSide === "top" ? -height : parent.height

                    x: Theme.snap((parent.width - width) / 2, overlayWindow.dpr)
                    y: {
                        if (!Theme.isConnectedEffect)
                            return Theme.snap(_centerY, overlayWindow.dpr);
                        const rest = _connectedRestY;
                        const collapsed = _connectedCollapsedY;
                        return Theme.snap(collapsed + (rest - collapsed) * slideMorph.value, overlayWindow.dpr);
                    }

                    readonly property int baseWidth: overlayWindow.useSpotlightStyle ? LauncherMetrics.spotlightWidth : LauncherMetrics.sizeWidth(SettingsData.dankLauncherV2Size)
                    readonly property int baseHeight: LauncherMetrics.sizeHeight(SettingsData.dankLauncherV2Size, Theme.outlineWidth, LauncherMetrics.footerShown(SettingsData.dankLauncherV2Size))
                    readonly property real cornerRadius: overlayWindow.useSpotlightStyle ? LauncherMetrics.spotlightRadius(width) : Theme.windowRadius
                    readonly property real bottomRadius: overlayWindow.useSpotlightStyle ? LauncherMetrics.spotlightBottomRadius(width, height) : cornerRadius
                    width: Math.min(baseWidth, overlayWindow.screen.width - LauncherMetrics.screenMargin)
                    height: overlayWindow.useSpotlightStyle ? Math.ceil(overlayWindow.launcherContent?.implicitHeight ?? LauncherMetrics.pillHeight) : Math.min(baseHeight, overlayWindow.screen.height - LauncherMetrics.screenMargin)

                    readonly property bool animatingOut: overviewScope.isClosing && overlayWindow.isSpotlightScreen

                    readonly property var scaleSpringParams: Theme.springPreset("fast", Theme.expressiveDurations.fast)
                    readonly property var slideSpringParams: Theme.springPreset("default", Theme.popoutAnimationDuration)

                    function checkExitSettled() {
                        if (!spotlightContainer.animatingOut)
                            return;
                        const spring = Theme.isConnectedEffect ? slideMorph : scaleMorph;
                        if (!spring.running)
                            overviewScope.resetState();
                    }

                    SpringMotion {
                        id: scaleMorph
                        enabled: !Theme.isConnectedEffect
                        reducedMotion: Theme.expressiveDurations.fast <= 0
                        positionEpsilon: 0.001
                        velocityEpsilon: 0.001
                        stiffness: spotlightContainer.scaleSpringParams.stiffness
                        damping: spotlightContainer.scaleSpringParams.damping
                        value: overlayWindow.shouldShowSpotlight ? 1 : 0

                        Component.onCompleted: snapTo(overlayWindow.shouldShowSpotlight ? 1 : 0)
                        onRunningChanged: spotlightContainer.checkExitSettled()
                    }

                    SpringMotion {
                        id: slideMorph
                        enabled: Theme.isConnectedEffect
                        reducedMotion: Theme.popoutAnimationDuration <= 0
                        positionEpsilon: 0.05
                        velocityEpsilon: 0.05
                        stiffness: spotlightContainer.slideSpringParams.stiffness
                        damping: spotlightContainer.slideSpringParams.damping
                        value: overlayWindow.shouldShowSpotlight ? 1 : 0

                        Component.onCompleted: snapTo(overlayWindow.shouldShowSpotlight ? 1 : 0)
                        onRunningChanged: spotlightContainer.checkExitSettled()
                    }

                    Connections {
                        target: overlayWindow
                        function onShouldShowSpotlightChanged() {
                            scaleMorph.retarget(overlayWindow.shouldShowSpotlight ? 1 : 0);
                            slideMorph.retarget(overlayWindow.shouldShowSpotlight ? 1 : 0);
                            spotlightContainer.checkExitSettled();
                        }
                    }

                    scale: Theme.isConnectedEffect ? 1.0 : (0.96 + 0.04 * scaleMorph.value)
                    opacity: Theme.isConnectedEffect ? 1 : (overlayWindow.shouldShowSpotlight ? 1 : 0)
                    visible: overlayWindow.shouldShowSpotlight || animatingOut
                    enabled: overlayWindow.shouldShowSpotlight

                    layer.enabled: visible
                    layer.smooth: false
                    layer.textureSize: layer.enabled ? Qt.size(Math.round(width * overlayWindow.dpr), Math.round(height * overlayWindow.dpr)) : Qt.size(0, 0)

                    Behavior on opacity {
                        enabled: !Theme.isConnectedEffect
                        NumberAnimation {
                            duration: Theme.expressiveDurations.fast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: spotlightContainer.visible ? Theme.expressiveCurves.expressiveFastSpatial : Theme.expressiveCurves.standardAccel
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.floatingWindowSurface
                        radius: spotlightContainer.cornerRadius
                        bottomLeftRadius: spotlightContainer.bottomRadius
                        bottomRightRadius: spotlightContainer.bottomRadius
                        border.color: Theme.outlineMedium
                        border.width: overlayWindow.useSpotlightStyle ? 0 : 1
                    }

                    FocusScope {
                        anchors.fill: parent
                        focus: true

                        Keys.onPressed: event => overlayWindow.launcherContent?.activeContextMenu?.handleKey(event)

                        Keys.onEscapePressed: event => {
                            overlayWindow.launcherContent?.activeContextMenu?.handleKey(event);
                            if (!event.accepted)
                                overlayWindow.launcherContent?.parentModal?.hide();
                            event.accepted = true;
                        }

                        Loader {
                            id: fullLauncherLoader
                            anchors.fill: parent
                            active: !overlayWindow.useSpotlightStyle
                            sourceComponent: LauncherContent {
                                parentModal: overlayWindow.fakeParentModal
                            }
                        }

                        Loader {
                            id: spotlightLauncherLoader
                            anchors.fill: parent
                            active: overlayWindow.useSpotlightStyle
                            sourceComponent: SpotlightLauncherContent {
                                parentModal: overlayWindow.fakeParentModal
                            }
                        }

                        Connections {
                            target: overlayWindow.launcherContent?.searchField ?? null
                            function onTextChanged() {
                                if (overlayWindow.launcherContent.searchField.text.length > 0 || !overviewScope.searchActive)
                                    return;
                                overviewScope.hideSpotlight();
                            }
                        }

                        Connections {
                            target: overlayWindow.launcherContent?.controller ?? null
                            function onItemExecuted() {
                                overviewScope.releaseKeyboard = true;
                                if (overviewScope.closeOnItemExecuted)
                                    overviewScope.closeOverviewRequested();
                            }
                            function onModeChanged(mode) {
                                if (overlayWindow.launcherContent.controller.autoSwitchedToFiles)
                                    return;
                                overviewScope.lastModeChosen(mode);
                            }
                        }
                    }
                }
            }
        }
    }
}
