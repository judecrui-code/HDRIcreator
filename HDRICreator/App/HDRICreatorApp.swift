import SwiftUI

@main
struct HDRICreatorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ProjectStore()
    var body: some Scene {
        WindowGroup { HomeView().environmentObject(store).tint(Theme.accent) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .all
    static func set(_ m: UIInterfaceOrientationMask) {
        mask = m
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
