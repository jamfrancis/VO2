import SwiftUI
import Combine

public final class FileSaver: NSObject, ObservableObject {
    public let objectWillChange = ObservableObjectPublisher()
    public func saveAndShare(data: Data, suggestedName: String, ext: String = "workout", from controller: UIViewController) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(suggestedName).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            controller.present(avc, animated: true)
        } catch {
            print("File save/share failed: \(error)")
        }
    }
    
    public func saveAndShare(data: Data, suggestedName: String, from controller: UIViewController) {
        saveAndShare(data: data, suggestedName: suggestedName, ext: "workout", from: controller)
    }
}
