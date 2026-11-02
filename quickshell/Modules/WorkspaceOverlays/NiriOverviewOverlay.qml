import QtQuick
import Quickshell
import qs.Common
import qs.Services

Scope {
    OverviewLauncherOverlay {
        layerNamespace: "dms:niri-overview-spotlight"
        overviewOpen: NiriService.inOverview
        activeOutput: NiriService.currentOutput
        launcherStyle: SettingsData.niriOverviewLauncherStyle
        lastMode: SessionData.niriOverviewLastMode
        onCloseOverviewRequested: NiriService.closeOverview()
        onFocusLeftRequested: NiriService.focusColumnLeft()
        onFocusRightRequested: NiriService.focusColumnRight()
        onFocusUpRequested: NiriService.send({
                "Action": {
                    "FocusWorkspaceUp": {}
                }
            })
        onFocusDownRequested: NiriService.send({
                "Action": {
                    "FocusWorkspaceDown": {}
                }
            })
        onLastModeChosen: mode => SessionData.setNiriOverviewLastMode(mode)
    }
}
