import UIKit

// MARK: - Report Style

/// Encapsulates all visual theming for PDF report generation.
/// Each preset provides a distinct look and feel while keeping
/// the same data and layout structure.
struct ReportStyle: Sendable, Identifiable, CaseIterable {
    let id: String
    let name: String
    let previewDescription: String

    // Fonts
    let titleFont: UIFont
    let sectionFont: UIFont
    let sectionHeaderFont: UIFont
    let sectionSubtitleFont: UIFont
    let bodyFont: UIFont
    let bodyMediumFont: UIFont
    let captionFont: UIFont
    let captionBoldFont: UIFont
    let monoFont: UIFont
    let monoBoldFont: UIFont
    let tinyFont: UIFont
    let tinyBoldFont: UIFont

    // Colors
    let accentColor: UIColor
    let primaryTextColor: UIColor
    let secondaryTextColor: UIColor
    let mutedTextColor: UIColor
    let borderColor: UIColor
    let stripeColor: UIColor
    let tableHeaderBackground: UIColor
    let tableHeaderForeground: UIColor

    // Chart styling
    let chartLineWidth: CGFloat
    let chartDotRadius: CGFloat
    let chartFillOpacity: CGFloat
    let chartZoneOpacity: CGFloat
    let barCornerRadius: CGFloat
    let barOpacity: CGFloat
    let gridLineWidth: CGFloat
    let gridColor: UIColor

    // Section header style
    let sectionBarHeight: CGFloat
    let headerRuleWidth: CGFloat
    let footerText: String

    // MARK: - CaseIterable

    static var allCases: [ReportStyle] { [.classic, .modern, .clinical] }

    // MARK: - Classic (current look)

    static let classic = ReportStyle(
        id: "classic",
        name: "Classic",
        previewDescription: "Professional blue-accented design with clean tables",
        titleFont: .systemFont(ofSize: 24, weight: .bold),
        sectionFont: .systemFont(ofSize: 12, weight: .bold),
        sectionHeaderFont: .systemFont(ofSize: 14, weight: .bold),
        sectionSubtitleFont: .systemFont(ofSize: 11, weight: .medium),
        bodyFont: .systemFont(ofSize: 10),
        bodyMediumFont: .systemFont(ofSize: 10, weight: .medium),
        captionFont: .systemFont(ofSize: 8),
        captionBoldFont: .systemFont(ofSize: 8, weight: .bold),
        monoFont: .monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        monoBoldFont: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
        tinyFont: .monospacedDigitSystemFont(ofSize: 7, weight: .regular),
        tinyBoldFont: .systemFont(ofSize: 7, weight: .medium),
        accentColor: UIColor(red: 0.15, green: 0.30, blue: 0.55, alpha: 1),
        primaryTextColor: UIColor(white: 0.10, alpha: 1),
        secondaryTextColor: UIColor(white: 0.25, alpha: 1),
        mutedTextColor: UIColor(white: 0.50, alpha: 1),
        borderColor: UIColor(white: 0.78, alpha: 1),
        stripeColor: UIColor(white: 0.95, alpha: 1),
        tableHeaderBackground: UIColor(red: 0.15, green: 0.30, blue: 0.55, alpha: 1),
        tableHeaderForeground: .white,
        chartLineWidth: 1.2,
        chartDotRadius: 2.0,
        chartFillOpacity: 0.08,
        chartZoneOpacity: 0.08,
        barCornerRadius: 1.5,
        barOpacity: 0.7,
        gridLineWidth: 0.4,
        gridColor: UIColor(white: 0.90, alpha: 1),
        sectionBarHeight: 3,
        headerRuleWidth: 1.5,
        footerText: "Neo Health Export  |  Health Report"
    )

    // MARK: - Modern (rounded, softer palette)

    static let modern = ReportStyle(
        id: "modern",
        name: "Modern",
        previewDescription: "Rounded fonts with a softer teal and green palette",
        titleFont: .systemFont(ofSize: 26, weight: .heavy),
        sectionFont: .systemFont(ofSize: 12, weight: .semibold),
        sectionHeaderFont: .systemFont(ofSize: 15, weight: .bold),
        sectionSubtitleFont: .systemFont(ofSize: 11, weight: .regular),
        bodyFont: .systemFont(ofSize: 10),
        bodyMediumFont: .systemFont(ofSize: 10, weight: .medium),
        captionFont: .systemFont(ofSize: 8),
        captionBoldFont: .systemFont(ofSize: 8, weight: .semibold),
        monoFont: .monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        monoBoldFont: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
        tinyFont: .monospacedDigitSystemFont(ofSize: 7, weight: .regular),
        tinyBoldFont: .systemFont(ofSize: 7, weight: .medium),
        accentColor: UIColor(red: 0.10, green: 0.50, blue: 0.48, alpha: 1),
        primaryTextColor: UIColor(white: 0.12, alpha: 1),
        secondaryTextColor: UIColor(white: 0.30, alpha: 1),
        mutedTextColor: UIColor(white: 0.48, alpha: 1),
        borderColor: UIColor(white: 0.82, alpha: 1),
        stripeColor: UIColor(red: 0.93, green: 0.97, blue: 0.96, alpha: 1),
        tableHeaderBackground: UIColor(red: 0.10, green: 0.50, blue: 0.48, alpha: 1),
        tableHeaderForeground: .white,
        chartLineWidth: 1.6,
        chartDotRadius: 2.5,
        chartFillOpacity: 0.12,
        chartZoneOpacity: 0.10,
        barCornerRadius: 3.0,
        barOpacity: 0.65,
        gridLineWidth: 0.3,
        gridColor: UIColor(white: 0.92, alpha: 1),
        sectionBarHeight: 4,
        headerRuleWidth: 2.0,
        footerText: "Neo Health Export  ·  Health Report"
    )

    // MARK: - Clinical (serif, minimal)

    static let clinical: ReportStyle = {
        let serifTitle = UIFont(name: "Georgia-Bold", size: 22) ?? .systemFont(ofSize: 22, weight: .bold)
        let serifSection = UIFont(name: "Georgia-Bold", size: 11) ?? .systemFont(ofSize: 11, weight: .bold)
        let serifHeader = UIFont(name: "Georgia-Bold", size: 13) ?? .systemFont(ofSize: 13, weight: .bold)
        let serifSubtitle = UIFont(name: "Georgia-Italic", size: 10) ?? .systemFont(ofSize: 10, weight: .regular)
        let serifBody = UIFont(name: "Georgia", size: 9.5) ?? .systemFont(ofSize: 9.5)
        let serifBodyMed = UIFont(name: "Georgia-Bold", size: 9.5) ?? .systemFont(ofSize: 9.5, weight: .medium)

        return ReportStyle(
            id: "clinical",
            name: "Clinical",
            previewDescription: "Serif fonts with minimal color for a medical-grade look",
            titleFont: serifTitle,
            sectionFont: serifSection,
            sectionHeaderFont: serifHeader,
            sectionSubtitleFont: serifSubtitle,
            bodyFont: serifBody,
            bodyMediumFont: serifBodyMed,
            captionFont: .systemFont(ofSize: 7.5),
            captionBoldFont: .systemFont(ofSize: 7.5, weight: .bold),
            monoFont: .monospacedDigitSystemFont(ofSize: 8.5, weight: .regular),
            monoBoldFont: .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            tinyFont: .monospacedDigitSystemFont(ofSize: 7, weight: .regular),
            tinyBoldFont: .systemFont(ofSize: 7, weight: .medium),
            accentColor: UIColor(white: 0.15, alpha: 1),
            primaryTextColor: UIColor(white: 0.08, alpha: 1),
            secondaryTextColor: UIColor(white: 0.22, alpha: 1),
            mutedTextColor: UIColor(white: 0.45, alpha: 1),
            borderColor: UIColor(white: 0.70, alpha: 1),
            stripeColor: UIColor(white: 0.96, alpha: 1),
            tableHeaderBackground: UIColor(white: 0.15, alpha: 1),
            tableHeaderForeground: .white,
            chartLineWidth: 1.0,
            chartDotRadius: 1.5,
            chartFillOpacity: 0.05,
            chartZoneOpacity: 0.06,
            barCornerRadius: 0,
            barOpacity: 0.55,
            gridLineWidth: 0.3,
            gridColor: UIColor(white: 0.88, alpha: 1),
            sectionBarHeight: 1.5,
            headerRuleWidth: 1.0,
            footerText: "Neo Health Export  —  Health Report"
        )
    }()
}
