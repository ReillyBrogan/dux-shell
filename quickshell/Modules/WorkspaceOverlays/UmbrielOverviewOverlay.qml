import QtQuick
import Quickshell
import qs.Common
import qs.Services

Scope {
    OverviewLauncherOverlay {
        layerNamespace: "dms:umbriel-overview-spotlight"
        overviewOpen: UmbrielService.overviewOpen
        activeOutput: UmbrielService.focusedOutput
        launcherStyle: SettingsData.umbrielOverviewLauncherStyle
        lastMode: SessionData.umbrielOverviewLastMode
        dismissModalOnOpen: true
        closeOnItemExecuted: SettingsData.closeOverviewOnWindowFocus
        onCloseOverviewRequested: UmbrielService.sendAction("overview-close")
        onFocusLeftRequested: UmbrielService.sendAction("window-focus-left")
        onFocusRightRequested: UmbrielService.sendAction("window-focus-right")
        onFocusUpRequested: UmbrielService.sendAction("window-focus-or-workspace-up")
        onFocusDownRequested: UmbrielService.sendAction("window-focus-or-workspace-down")
        onLastModeChosen: mode => SessionData.setUmbrielOverviewLastMode(mode)
    }
}
