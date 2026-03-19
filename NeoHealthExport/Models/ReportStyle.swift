import UIKit

// MARK: - Layout Variant

enum LayoutVariant: Sendable {
    case dashboard   // Classic — card-based, accent banner
    case editorial   // Modern — spacious, premium, soft backgrounds
    case document    // Clinical — dense, medical, traditional tables
}

// MARK: - Report Style

/// Encapsulates all visual theming for PDF report generation.
/// Each preset provides a distinct look and feel while keeping
/// the same data and layout structure.
struct ReportStyle: Sendable, Identifiable, Hashable, CaseIterable {
    static func == (lhs: ReportStyle, rhs: ReportStyle) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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

    // Layout
    let footerText: String

    // Dashboard card styling
    let cardCornerRadius: CGFloat
    let cardBackground: UIColor
    let headerBackground: UIColor
    let layoutVariant: LayoutVariant

    // MARK: - CaseIterable

    static var allCases: [ReportStyle] { [.classic, .modern, .clinical] }

    // MARK: - Classic — Clean, minimal, inspired by modern health reports

    static let classic = ReportStyle(
        id: "classic",
        name: "Classic",
        previewDescription: "Clean and professional with a subtle blue accent",
        titleFont: .systemFont(ofSize: 22, weight: .semibold),
        sectionFont: .systemFont(ofSize: 11, weight: .semibold),
        sectionHeaderFont: .systemFont(ofSize: 15, weight: .bold),
        sectionSubtitleFont: .systemFont(ofSize: 10, weight: .regular),
        bodyFont: .systemFont(ofSize: 10),
        bodyMediumFont: .systemFont(ofSize: 10, weight: .medium),
        captionFont: .systemFont(ofSize: 8),
        captionBoldFont: .systemFont(ofSize: 8, weight: .semibold),
        monoFont: .monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        monoBoldFont: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
        tinyFont: .monospacedDigitSystemFont(ofSize: 7, weight: .regular),
        tinyBoldFont: .systemFont(ofSize: 7, weight: .medium),
        accentColor: UIColor(red: 0.18, green: 0.22, blue: 0.35, alpha: 1),     // slate-800
        primaryTextColor: UIColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1), // gray-900
        secondaryTextColor: UIColor(red: 0.30, green: 0.33, blue: 0.38, alpha: 1), // gray-600
        mutedTextColor: UIColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1),   // gray-400
        borderColor: UIColor(red: 0.90, green: 0.91, blue: 0.92, alpha: 1),      // gray-200
        stripeColor: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1),      // gray-50
        tableHeaderBackground: UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1), // gray-100
        tableHeaderForeground: UIColor(red: 0.18, green: 0.22, blue: 0.35, alpha: 1), // slate-800
        chartLineWidth: 1.2,
        chartDotRadius: 1.8,
        chartFillOpacity: 0.06,
        chartZoneOpacity: 0.05,
        barCornerRadius: 2.0,
        barOpacity: 0.6,
        gridLineWidth: 0.3,
        gridColor: UIColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1),        // gray-150
        footerText: "Neo Health Export  ·  Health Report",
        cardCornerRadius: 6,
        cardBackground: UIColor(red: 0.98, green: 0.985, blue: 1.0, alpha: 1),
        headerBackground: UIColor(red: 0.18, green: 0.22, blue: 0.35, alpha: 1),
        layoutVariant: .dashboard
    )

    // MARK: - Modern — Teal accent, slightly warmer

    static let modern = ReportStyle(
        id: "modern",
        name: "Modern",
        previewDescription: "Contemporary design with a warm teal accent",
        titleFont: .systemFont(ofSize: 22, weight: .bold),
        sectionFont: .systemFont(ofSize: 11, weight: .semibold),
        sectionHeaderFont: .systemFont(ofSize: 15, weight: .bold),
        sectionSubtitleFont: .systemFont(ofSize: 10, weight: .regular),
        bodyFont: .systemFont(ofSize: 10),
        bodyMediumFont: .systemFont(ofSize: 10, weight: .medium),
        captionFont: .systemFont(ofSize: 8),
        captionBoldFont: .systemFont(ofSize: 8, weight: .semibold),
        monoFont: .monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        monoBoldFont: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
        tinyFont: .monospacedDigitSystemFont(ofSize: 7, weight: .regular),
        tinyBoldFont: .systemFont(ofSize: 7, weight: .medium),
        accentColor: UIColor(red: 0.08, green: 0.38, blue: 0.38, alpha: 1),      // teal-800
        primaryTextColor: UIColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1),
        secondaryTextColor: UIColor(red: 0.30, green: 0.33, blue: 0.38, alpha: 1),
        mutedTextColor: UIColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1),
        borderColor: UIColor(red: 0.90, green: 0.92, blue: 0.92, alpha: 1),
        stripeColor: UIColor(red: 0.96, green: 0.98, blue: 0.98, alpha: 1),
        tableHeaderBackground: UIColor(red: 0.94, green: 0.97, blue: 0.97, alpha: 1),
        tableHeaderForeground: UIColor(red: 0.08, green: 0.38, blue: 0.38, alpha: 1),
        chartLineWidth: 1.4,
        chartDotRadius: 2.0,
        chartFillOpacity: 0.08,
        chartZoneOpacity: 0.06,
        barCornerRadius: 3.0,
        barOpacity: 0.55,
        gridLineWidth: 0.3,
        gridColor: UIColor(red: 0.93, green: 0.94, blue: 0.94, alpha: 1),
        footerText: "Neo Health Export  ·  Health Report",
        cardCornerRadius: 10,
        cardBackground: UIColor(red: 0.97, green: 0.99, blue: 0.99, alpha: 1),
        headerBackground: UIColor(red: 0.08, green: 0.38, blue: 0.38, alpha: 1),
        layoutVariant: .editorial
    )

    // MARK: - Clinical — Serif, minimal, medical-grade

    static let clinical: ReportStyle = {
        let serifTitle = UIFont(name: "Georgia-Bold", size: 20) ?? .systemFont(ofSize: 20, weight: .bold)
        let serifSection = UIFont(name: "Georgia-Bold", size: 10.5) ?? .systemFont(ofSize: 10.5, weight: .bold)
        let serifHeader = UIFont(name: "Georgia-Bold", size: 13) ?? .systemFont(ofSize: 13, weight: .bold)
        let serifSubtitle = UIFont(name: "Georgia-Italic", size: 9.5) ?? .systemFont(ofSize: 9.5, weight: .regular)
        let serifBody = UIFont(name: "Georgia", size: 9.5) ?? .systemFont(ofSize: 9.5)
        let serifBodyMed = UIFont(name: "Georgia-Bold", size: 9.5) ?? .systemFont(ofSize: 9.5, weight: .medium)

        return ReportStyle(
            id: "clinical",
            name: "Clinical",
            previewDescription: "Serif typeface with minimal color for a medical-grade look",
            titleFont: serifTitle,
            sectionFont: serifSection,
            sectionHeaderFont: serifHeader,
            sectionSubtitleFont: serifSubtitle,
            bodyFont: serifBody,
            bodyMediumFont: serifBodyMed,
            captionFont: .systemFont(ofSize: 7.5),
            captionBoldFont: .systemFont(ofSize: 7.5, weight: .semibold),
            monoFont: .monospacedDigitSystemFont(ofSize: 8.5, weight: .regular),
            monoBoldFont: .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            tinyFont: .monospacedDigitSystemFont(ofSize: 7, weight: .regular),
            tinyBoldFont: .systemFont(ofSize: 7, weight: .medium),
            accentColor: UIColor(white: 0.15, alpha: 1),
            primaryTextColor: UIColor(white: 0.08, alpha: 1),
            secondaryTextColor: UIColor(white: 0.25, alpha: 1),
            mutedTextColor: UIColor(white: 0.50, alpha: 1),
            borderColor: UIColor(white: 0.88, alpha: 1),
            stripeColor: UIColor(white: 0.97, alpha: 1),
            tableHeaderBackground: UIColor(white: 0.94, alpha: 1),
            tableHeaderForeground: UIColor(white: 0.15, alpha: 1),
            chartLineWidth: 1.0,
            chartDotRadius: 1.5,
            chartFillOpacity: 0.04,
            chartZoneOpacity: 0.04,
            barCornerRadius: 0,
            barOpacity: 0.50,
            gridLineWidth: 0.25,
            gridColor: UIColor(white: 0.90, alpha: 1),
            footerText: "Neo Health Export  —  Health Report",
            cardCornerRadius: 2,
            cardBackground: UIColor(white: 0.985, alpha: 1),
            headerBackground: UIColor(white: 0.15, alpha: 1),
            layoutVariant: .document
        )
    }()
}
