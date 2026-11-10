import AVFoundation
import SwiftUI

@main
struct KitePrepApp: App {
    init() {
        // Lets the read-aloud voice in lessons and videos play even when the silent switch is on,
        // mixed with any music that's already playing.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
    }

    var body: some Scene {
        WindowGroup {
            KiteWebView()
                .ignoresSafeArea()
                .background(Color("Backdrop").ignoresSafeArea())
        }
    }
}
