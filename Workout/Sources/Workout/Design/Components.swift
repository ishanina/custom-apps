import SwiftUI
import AVFoundation

// MARK: - Badges & bars

struct TypeBadge: View {
    let type: StepType
    var size: CGFloat = 32
    var solid = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(solid ? AnyShapeStyle(type.tint.gradient) : AnyShapeStyle(type.tint.opacity(0.16)))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(type.tint.opacity(solid ? 0 : 0.28), lineWidth: 1)
            )
            .overlay(
                Image(systemName: type.symbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(solid ? Color.white : type.tint)
            )
            .frame(width: size, height: size)
    }
}

/// A thin bar whose segments show the mix of step types, proportional to length.
struct CompositionBar: View {
    let steps: [Step]
    var height: CGFloat = 6
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            if steps.isEmpty {
                Capsule().fill(Color.white.opacity(0.07))
            } else {
                let total = steps.reduce(0) { $0 + $1.visualWeight }
                let available = geo.size.width - spacing * CGFloat(steps.count - 1)
                HStack(spacing: spacing) {
                    ForEach(steps) { step in
                        Capsule()
                            .fill(step.type.tint)
                            .frame(width: max(1.5, available * step.visualWeight / total))
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: height)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, large: large)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let large: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.rounded(large ? 15 : 13, .bold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, large ? 22 : 14)
            .padding(.vertical, large ? 10 : 6)
            .background(Capsule().fill(Theme.accent.opacity(isEnabled ? 1 : 0.25)))
            .brightness(hovering && isEnabled ? 0.05 : 0)
            .shadow(color: Theme.accent.opacity(isEnabled ? (hovering ? 0.4 : 0.18) : 0), radius: hovering ? 16 : 10, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.rounded(13, .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : hovering ? 0.12 : 0.08)))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}

/// Round, borderless icon button that lights up on hover.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 36
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size, active: active)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let active: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(active ? Theme.accent : Color.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.18 : hovering ? 0.1 : 0)))
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.rounded(12, .semibold))
                .monospacedDigit()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Theme.accentInk : Color.primary)
                .background(Capsule().fill(selected ? Theme.accent : Color.white.opacity(hovering ? 0.12 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Inputs

struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = .system(size: 13)
    var alignment: TextAlignment = .leading
    var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(invalid ? Color.red.opacity(0.8) : focused ? Theme.accent.opacity(0.7) : Theme.hairline,
                                  lineWidth: focused || invalid ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// Accepts "90", "1:30" or "1:02:30".
struct TimeField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 92

    var body: some View {
        InputField(placeholder: placeholder, text: $text,
                   font: .rounded(14, .medium).monospacedDigit(),
                   alignment: .center,
                   invalid: Fmt.parseTime(text) == nil)
            .frame(width: width)
    }
}

struct FormRow<Content: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            content
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

struct StatLabel: View {
    let icon: String
    let text: String
    var body: some View {
        Label {
            Text(text).monospacedDigit()
        } icon: {
            Image(systemName: icon).foregroundStyle(.tertiary)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Type tile

struct TypeTile: View {
    let type: StepType
    var selected = false
    var showsBlurb = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                TypeBadge(type: type, size: showsBlurb ? 40 : 34, solid: selected || (showsBlurb && hovering))
                Text(type.title).font(.system(size: 13, weight: .semibold))
                if showsBlurb {
                    Text(type.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, showsBlurb ? 18 : 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? type.tint.opacity(0.13) : Color.white.opacity(hovering ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? type.tint.opacity(0.65) : hovering ? type.tint.opacity(0.35) : Theme.hairline, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Video thumbnails

struct VideoThumbnail: View {
    let step: Step

    var body: some View {
        if let id = step.youtubeID {
            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
        } else if step.videoSource == .local, let path = step.localPath {
            LocalThumbnail(path: path, time: step.startTime)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.video.opacity(0.14)
            Image(systemName: "play.rectangle.fill").foregroundStyle(Theme.video)
        }
    }
}

private struct LocalThumbnail: View {
    let path: String
    let time: TimeInterval
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Theme.video.opacity(0.14)
                Image(systemName: "film").foregroundStyle(Theme.video)
            }
        }
        .task(id: "\(path)@\(time)") {
            image = await ThumbnailCache.shared.image(path: path, time: time)
        }
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(path: String, time: TimeInterval) async -> NSImage? {
        let key = "\(path)@\(Int(time))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        // Skip the usually-black first frames when the clip starts at 0.
        for seconds in [time > 0 ? time : 8, 0] {
            if let (cg, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                cache.setObject(image, forKey: key)
                return image
            }
        }
        return nil
    }
}
