import CoreText
import SwiftUI
import UIKit

enum StacksFontRegistration {
    static func registerBundledFonts() {
        let fonts = [
            ("InstrumentSerif-Regular", "ttf"),
            ("WinkyRough-Black", "ttf")
        ]

        for (name, extensionName) in fonts {
            guard let url = Bundle.main.url(forResource: name, withExtension: extensionName) else {
                continue
            }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func stacksDisplay(size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func stacksText(size: CGFloat, weight: Weight = .thin) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func stacksHeader(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func stacksSerifDisplay(size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func stacksOnboardingSerif(size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }

    static func instrumentSerifItalic(size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size).italic()
    }

    static func stacksMasthead(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
}

enum StackTitleTokens {
    // Matches the simple SF Pro Display Bold "Hello" treatment used by the
    // Stack header reference: prominent but not a poster-sized masthead.
    static let stackTitleMaximumFontSize: CGFloat = 64
    static let stackTitleMinimumFontSize: CGFloat = 28
    static let stackTitleWeight: Font.Weight = .bold
    // SF Pro Display Bold (700) has its intended rhythm at standard tracking.
    static let stackTitleTrackingRatio: CGFloat = 0
    static let stackTitleLineLimit = 1
    static let stackTitleHorizontalMargin: CGFloat = 16
}

enum StackTitleMetrics {
    static func resolvedFontSize(for text: String, availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return StackTitleTokens.stackTitleMaximumFontSize }

        let maximum = StackTitleTokens.stackTitleMaximumFontSize
        let minimum = StackTitleTokens.stackTitleMinimumFontSize

        for step in stride(from: maximum, through: minimum, by: -0.25) {
            if measuredWidth(for: text, fontSize: step) <= availableWidth {
                return step
            }
        }

        return minimum
    }

    static func lineHeight(for fontSize: CGFloat) -> CGFloat {
        ceil(mastheadFont(ofSize: fontSize).lineHeight + 4)
    }

    private static func measuredWidth(for text: String, fontSize: CGFloat) -> CGFloat {
        NSAttributedString(
            string: text,
            attributes: [
                .font: mastheadFont(ofSize: fontSize),
                .kern: fontSize * StackTitleTokens.stackTitleTrackingRatio
            ]
        ).size().width
    }

    private static func mastheadFont(ofSize size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .bold)
    }

}

struct StackTitle: View {
    let text: String

    @State private var resolvedFontSize = StackTitleTokens.stackTitleMaximumFontSize

    var body: some View {
        GeometryReader { proxy in
            let fontSize = StackTitleMetrics.resolvedFontSize(
                for: text,
                availableWidth: proxy.size.width
            )

            title(fontSize: fontSize, availableWidth: proxy.size.width)
                .onAppear {
                    resolvedFontSize = fontSize
                }
                .onChange(of: proxy.size.width) { _, _ in
                    resolvedFontSize = fontSize
                }
                .onChange(of: text) { _, _ in
                    resolvedFontSize = fontSize
                }
        }
        .frame(height: StackTitleMetrics.lineHeight(for: resolvedFontSize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func title(fontSize: CGFloat, availableWidth: CGFloat) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .default))
            .tracking(fontSize * StackTitleTokens.stackTitleTrackingRatio)
            .lineLimit(StackTitleTokens.stackTitleLineLimit)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: availableWidth, alignment: .leading)
            .frame(height: StackTitleMetrics.lineHeight(for: fontSize), alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
