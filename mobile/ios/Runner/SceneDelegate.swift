import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    forward(connectionOptions.urlContexts)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)
    forward(URLContexts)
  }

  private func forward(_ contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      NotificationCenter.default.post(
        name: Notification.Name("MetaWearablesDatHandleURL"),
        object: nil,
        userInfo: ["url": context.url]
      )
    }
  }
}
