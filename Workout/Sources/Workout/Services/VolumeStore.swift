import Foundation

/// Remembers the volume chosen for each video / playlist.
final class VolumeStore {
    static let shared = VolumeStore()
    private let defaults = UserDefaults.standard
    private let prefix = "volume_"

    func volume(for key: String, default defaultVolume: Int) -> Int {
        (defaults.object(forKey: prefix + key) as? Int) ?? defaultVolume
    }

    func setVolume(_ volume: Int, for key: String) {
        defaults.set(volume, forKey: prefix + key)
    }
}
