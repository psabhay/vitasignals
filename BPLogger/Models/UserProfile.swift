import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var gender: String
    var doctorName: String
    var medicalNotes: String

    init(
        name: String = "",
        age: Int = 0,
        heightCm: Double = 0,
        weightKg: Double = 0,
        gender: String = "",
        doctorName: String = "",
        medicalNotes: String = ""
    ) {
        self.name = name
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.gender = gender
        self.doctorName = doctorName
        self.medicalNotes = medicalNotes
    }

    var bmi: Double? {
        guard heightCm > 0, weightKg > 0 else { return nil }
        let heightM = heightCm / 100
        return weightKg / (heightM * heightM)
    }

    var bmiCategory: String {
        guard let bmi else { return "" }
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }

    var heightFormatted: String {
        guard heightCm > 0 else { return "" }
        let totalInches = heightCm / 2.54
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        return "\(feet)'\(inches)\" (\(Int(heightCm)) cm)"
    }

    var weightFormatted: String {
        guard weightKg > 0 else { return "" }
        let lbs = weightKg * 2.20462
        return String(format: "%.0f kg (%.0f lbs)", weightKg, lbs)
    }
}
