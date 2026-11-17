import SwiftUI
private struct LaunchCoverKey:EnvironmentKey {static let defaultValue=false}
extension EnvironmentValues {var launchIsCovering:Bool {get{self[LaunchCoverKey.self]} set{self[LaunchCoverKey.self]=newValue}}}
struct LaunchGateRoot<Content:View>:View {
    let manager:LaunchGateManager
    @ViewBuilder let content:()->Content
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        ZStack {content().environment(\.launchIsCovering,manager.isCovering).disabled(manager.isCovering).accessibilityHidden(manager.isCovering)
            if manager.isCovering {Color.white.ignoresSafeArea().zIndex(100).accessibilityHidden(true)}
        }.statusBarHidden(manager.isCovering)
        .task {manager.start(isActive:scenePhase == .active)}
        .onChange(of:scenePhase) {_,phase in manager.sceneDidChange(isActive:phase == .active,isBackground:phase == .background)}
    }
}
