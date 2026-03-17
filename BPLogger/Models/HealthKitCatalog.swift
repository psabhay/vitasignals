import HealthKit
import SwiftUI

// MARK: - HealthKit Type Catalog
//
// Comprehensive catalog of HealthKit quantity types with metadata
// for auto-generating MetricDefinitions. This enables the app to
// discover and display any health metric the user has in Apple Health
// without needing explicit per-type UI code.

struct HealthKitCatalog {

    struct Entry {
        let identifier: HKQuantityTypeIdentifier
        let metricType: String
        let name: String
        let unit: () -> HKUnit
        let displayUnit: String
        let category: MetricCategory
        let isCumulative: Bool
        let icon: String
        let color: Color
        let referenceMin: Double?
        let referenceMax: Double?
        let inputMin: Double
        let inputMax: Double
        let inputStep: Double
        var description: String?

        func toMetricDefinition() -> MetricDefinition {
            MetricDefinition(
                type: metricType,
                name: name,
                unit: displayUnit,
                icon: icon,
                color: color,
                category: category,
                chartStyle: isCumulative ? .bar : .line,
                aggregation: isCumulative ? .sum : .average,
                referenceMin: referenceMin,
                referenceMax: referenceMax,
                inputMin: inputMin,
                inputMax: inputMax,
                inputStep: inputStep,
                hkQuantityType: identifier,
                hkUnit: unit,
                isCumulative: isCumulative,
                description: description
            )
        }
    }

    // MARK: - Lookup

    static func entry(forMetricType type: String) -> Entry? {
        entries.first { $0.metricType == type }
    }

    static func entry(for identifier: HKQuantityTypeIdentifier) -> Entry? {
        entries.first { $0.identifier == identifier }
    }

    static func definition(forMetricType type: String) -> MetricDefinition? {
        entry(forMetricType: type)?.toMetricDefinition()
    }

    static var allIdentifiers: [HKQuantityTypeIdentifier] {
        entries.map(\.identifier)
    }

    // MARK: - Complete Catalog

    static let entries: [Entry] = {
        var list: [Entry] = []

        // ───────────────────────────────────────
        // VITALS
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .heartRate, metricType: "heartRate",
            name: "Heart Rate", unit: { .count().unitDivided(by: .minute()) },
            displayUnit: "bpm", category: .vitals, isCumulative: false,
            icon: "heart.fill", color: .red,
            referenceMin: 60, referenceMax: 100,
            inputMin: 30, inputMax: 220, inputStep: 1,
            description: "Number of times your heart beats per minute, sampled throughout the day."
        ))

        list.append(Entry(
            identifier: .restingHeartRate, metricType: "restingHeartRate",
            name: "Resting Heart Rate", unit: { .count().unitDivided(by: .minute()) },
            displayUnit: "bpm", category: .vitals, isCumulative: false,
            icon: "heart.fill", color: .pink,
            referenceMin: 60, referenceMax: 100,
            inputMin: 30, inputMax: 220, inputStep: 1,
            description: "Heart rate measured when you've been inactive and calm for at least 10 minutes."
        ))

        list.append(Entry(
            identifier: .bodyTemperature, metricType: "bodyTemperature",
            name: "Body Temperature", unit: { .degreeCelsius() },
            displayUnit: "°C", category: .vitals, isCumulative: false,
            icon: "thermometer.medium", color: .red,
            referenceMin: 36.1, referenceMax: 37.2,
            inputMin: 34, inputMax: 42, inputStep: 0.1,
            description: "Core body temperature measured with a thermometer or wearable sensor."
        ))

        list.append(Entry(
            identifier: .basalBodyTemperature, metricType: "basalBodyTemperature",
            name: "Basal Body Temperature", unit: { .degreeCelsius() },
            displayUnit: "°C", category: .vitals, isCumulative: false,
            icon: "thermometer.low", color: .orange,
            referenceMin: 36.1, referenceMax: 36.7,
            inputMin: 34, inputMax: 42, inputStep: 0.01,
            description: "Lowest body temperature at rest, often tracked for fertility awareness."
        ))

        list.append(Entry(
            identifier: .bloodGlucose, metricType: "bloodGlucose",
            name: "Blood Glucose", unit: { .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)) },
            displayUnit: "mg/dL", category: .vitals, isCumulative: false,
            icon: "drop.fill", color: .red,
            referenceMin: 70, referenceMax: 100,
            inputMin: 20, inputMax: 600, inputStep: 1,
            description: "Concentration of glucose in your blood, important for diabetes management."
        ))

        list.append(Entry(
            identifier: .bloodAlcoholContent, metricType: "bloodAlcoholContent",
            name: "Blood Alcohol Content", unit: { .percent() },
            displayUnit: "%", category: .vitals, isCumulative: false,
            icon: "drop.triangle.fill", color: .purple,
            referenceMin: nil, referenceMax: 0.08,
            inputMin: 0, inputMax: 0.5, inputStep: 0.01,
            description: "Percentage of alcohol in your bloodstream."
        ))

        list.append(Entry(
            identifier: .peripheralPerfusionIndex, metricType: "peripheralPerfusionIndex",
            name: "Perfusion Index", unit: { .percent() },
            displayUnit: "%", category: .vitals, isCumulative: false,
            icon: "waveform.path", color: .pink,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 20, inputStep: 0.1,
            description: "Strength of blood flow to your extremities, measured via pulse oximetry."
        ))

        // ───────────────────────────────────────
        // CARDIO FITNESS
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .heartRateVariabilitySDNN, metricType: "heartRateVariability",
            name: "Heart Rate Variability", unit: { .secondUnit(with: .milli) },
            displayUnit: "ms", category: .cardioFitness, isCumulative: false,
            icon: "waveform.path.ecg", color: .purple,
            referenceMin: 20, referenceMax: nil,
            inputMin: 1, inputMax: 300, inputStep: 1,
            description: "Variation in time between heartbeats (SDNN), indicating autonomic nervous system balance."
        ))

        list.append(Entry(
            identifier: .vo2Max, metricType: "vo2Max",
            name: "VO2 Max", unit: { HKUnit(from: "ml/kg*min") },
            displayUnit: "mL/kg/min", category: .cardioFitness, isCumulative: false,
            icon: "lungs.fill", color: .orange,
            referenceMin: 20, referenceMax: 60,
            inputMin: 10, inputMax: 90, inputStep: 0.1,
            description: "Maximum oxygen your body can use during exercise, a key indicator of cardiorespiratory fitness."
        ))

        list.append(Entry(
            identifier: .walkingHeartRateAverage, metricType: "walkingHeartRate",
            name: "Walking Heart Rate", unit: { .count().unitDivided(by: .minute()) },
            displayUnit: "bpm", category: .cardioFitness, isCumulative: false,
            icon: "figure.walk", color: .red,
            referenceMin: nil, referenceMax: nil,
            inputMin: 40, inputMax: 200, inputStep: 1,
            description: "Average heart rate recorded while walking, reflecting cardiovascular efficiency during movement."
        ))

        list.append(Entry(
            identifier: .heartRateRecoveryOneMinute, metricType: "heartRateRecoveryOneMinute",
            name: "Heart Rate Recovery", unit: { .count().unitDivided(by: .minute()) },
            displayUnit: "bpm", category: .cardioFitness, isCumulative: false,
            icon: "heart.text.square", color: .teal,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100, inputStep: 1,
            description: "How quickly your heart rate drops one minute after stopping intense exercise."
        ))

        list.append(Entry(
            identifier: .atrialFibrillationBurden, metricType: "atrialFibrillationBurden",
            name: "AFib Burden", unit: { .percent() },
            displayUnit: "%", category: .cardioFitness, isCumulative: false,
            icon: "waveform.path.ecg.rectangle", color: .red,
            referenceMin: nil, referenceMax: 1,
            inputMin: 0, inputMax: 100, inputStep: 0.1,
            description: "Percentage of time your heart shows signs of irregular rhythm (atrial fibrillation)."
        ))

        // ───────────────────────────────────────
        // ACTIVITY
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .stepCount, metricType: "stepCount",
            name: "Steps", unit: { .count() },
            displayUnit: "steps", category: .activity, isCumulative: true,
            icon: "shoeprints.fill", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100000, inputStep: 100,
            description: "Total number of steps detected by your device throughout the day."
        ))

        list.append(Entry(
            identifier: .appleExerciseTime, metricType: "exerciseMinutes",
            name: "Exercise Minutes", unit: { .minute() },
            displayUnit: "min", category: .activity, isCumulative: true,
            icon: "flame.fill", color: .mint,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 600, inputStep: 1,
            description: "Minutes spent in activity at or above a brisk walk, as tracked by Apple Watch."
        ))

        list.append(Entry(
            identifier: .activeEnergyBurned, metricType: "activeEnergy",
            name: "Active Energy", unit: { .kilocalorie() },
            displayUnit: "kcal", category: .activity, isCumulative: true,
            icon: "bolt.fill", color: .yellow,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 5000, inputStep: 10,
            description: "Calories burned through movement and exercise above your resting metabolic rate."
        ))

        list.append(Entry(
            identifier: .basalEnergyBurned, metricType: "basalEnergyBurned",
            name: "Resting Energy", unit: { .kilocalorie() },
            displayUnit: "kcal", category: .activity, isCumulative: true,
            icon: "bolt.heart", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 5000, inputStep: 10,
            description: "Calories your body burns at rest to maintain basic functions like breathing."
        ))

        list.append(Entry(
            identifier: .distanceWalkingRunning, metricType: "distanceWalkingRunning",
            name: "Walking + Running Distance", unit: { .meterUnit(with: .kilo) },
            displayUnit: "km", category: .activity, isCumulative: true,
            icon: "figure.walk", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100, inputStep: 0.1,
            description: "Total distance covered while walking and running, measured by GPS and motion sensors."
        ))

        list.append(Entry(
            identifier: .distanceCycling, metricType: "distanceCycling",
            name: "Cycling Distance", unit: { .meterUnit(with: .kilo) },
            displayUnit: "km", category: .activity, isCumulative: true,
            icon: "bicycle", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 500, inputStep: 0.1,
            description: "Distance covered while cycling, measured by GPS and motion sensors."
        ))

        list.append(Entry(
            identifier: .distanceSwimming, metricType: "distanceSwimming",
            name: "Swimming Distance", unit: { .meter() },
            displayUnit: "m", category: .activity, isCumulative: true,
            icon: "figure.pool.swim", color: .cyan,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 20000, inputStep: 10,
            description: "Distance covered while swimming, estimated from stroke count and pool length."
        ))

        list.append(Entry(
            identifier: .flightsClimbed, metricType: "flightsClimbed",
            name: "Flights Climbed", unit: { .count() },
            displayUnit: "flights", category: .activity, isCumulative: true,
            icon: "figure.stairs", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 200, inputStep: 1,
            description: "Number of flights of stairs climbed, where one flight equals about 3 meters of elevation."
        ))

        list.append(Entry(
            identifier: .appleStandTime, metricType: "appleStandTime",
            name: "Stand Time", unit: { .minute() },
            displayUnit: "min", category: .activity, isCumulative: true,
            icon: "figure.stand", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 1440, inputStep: 1,
            description: "Minutes per day where you stood and moved for at least one minute per hour."
        ))

        list.append(Entry(
            identifier: .appleMoveTime, metricType: "appleMoveTime",
            name: "Move Time", unit: { .minute() },
            displayUnit: "min", category: .activity, isCumulative: true,
            icon: "figure.walk.motion", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 1440, inputStep: 1,
            description: "Total minutes spent actively moving throughout the day."
        ))

        list.append(Entry(
            identifier: .swimmingStrokeCount, metricType: "swimStrokeCount",
            name: "Swim Strokes", unit: { .count() },
            displayUnit: "strokes", category: .activity, isCumulative: true,
            icon: "figure.pool.swim", color: .cyan,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 10000, inputStep: 10,
            description: "Number of swim strokes counted during pool or open water swimming."
        ))

        list.append(Entry(
            identifier: .pushCount, metricType: "pushCount",
            name: "Wheelchair Pushes", unit: { .count() },
            displayUnit: "pushes", category: .activity, isCumulative: true,
            icon: "figure.roll", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 50000, inputStep: 10,
            description: "Number of wheelchair pushes detected throughout the day."
        ))

        list.append(Entry(
            identifier: .nikeFuel, metricType: "nikeFuel",
            name: "Nike Fuel", unit: { .count() },
            displayUnit: "NikeFuel", category: .activity, isCumulative: true,
            icon: "flame", color: .yellow,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 10000, inputStep: 10,
            description: "Activity metric from Nike measuring overall movement intensity."
        ))

        list.append(Entry(
            identifier: .runningSpeed, metricType: "runningSpeed",
            name: "Running Speed", unit: { .meter().unitDivided(by: .second()) },
            displayUnit: "m/s", category: .activity, isCumulative: false,
            icon: "figure.run", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 15, inputStep: 0.1,
            description: "Your pace while running, measured in meters per second."
        ))

        list.append(Entry(
            identifier: .runningPower, metricType: "runningPower",
            name: "Running Power", unit: { .watt() },
            displayUnit: "W", category: .activity, isCumulative: false,
            icon: "figure.run", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 1000, inputStep: 1,
            description: "Estimated mechanical power output while running, measured in watts."
        ))

        list.append(Entry(
            identifier: .cyclingSpeed, metricType: "cyclingSpeed",
            name: "Cycling Speed", unit: { .meter().unitDivided(by: .second()) },
            displayUnit: "m/s", category: .activity, isCumulative: false,
            icon: "bicycle", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 30, inputStep: 0.1,
            description: "Your pace while cycling, measured in meters per second."
        ))

        list.append(Entry(
            identifier: .cyclingPower, metricType: "cyclingPower",
            name: "Cycling Power", unit: { .watt() },
            displayUnit: "W", category: .activity, isCumulative: false,
            icon: "bicycle", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 2000, inputStep: 1,
            description: "Mechanical power output while cycling, measured by a power meter in watts."
        ))

        list.append(Entry(
            identifier: .cyclingCadence, metricType: "cyclingCadence",
            name: "Cycling Cadence", unit: { .count().unitDivided(by: .minute()) },
            displayUnit: "rpm", category: .activity, isCumulative: false,
            icon: "bicycle", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 200, inputStep: 1,
            description: "Pedal revolutions per minute while cycling."
        ))

        // ───────────────────────────────────────
        // BODY
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .bodyMass, metricType: "bodyMass",
            name: "Weight", unit: { .gramUnit(with: .kilo) },
            displayUnit: "kg", category: .body, isCumulative: false,
            icon: "scalemass", color: .brown,
            referenceMin: nil, referenceMax: nil,
            inputMin: 20, inputMax: 300, inputStep: 0.1,
            description: "Your body weight as measured or entered manually."
        ))

        list.append(Entry(
            identifier: .bodyMassIndex, metricType: "bodyMassIndex",
            name: "BMI", unit: { .count() },
            displayUnit: "kg/m²", category: .body, isCumulative: false,
            icon: "figure.arms.open", color: .orange,
            referenceMin: 18.5, referenceMax: 25,
            inputMin: 10, inputMax: 60, inputStep: 0.1,
            description: "Body mass divided by height squared, a screening tool for weight categories."
        ))

        list.append(Entry(
            identifier: .bodyFatPercentage, metricType: "bodyFatPercentage",
            name: "Body Fat", unit: { .percent() },
            displayUnit: "%", category: .body, isCumulative: false,
            icon: "figure.arms.open", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 2, inputMax: 60, inputStep: 0.1,
            description: "Proportion of your total body weight that is fat tissue."
        ))

        list.append(Entry(
            identifier: .leanBodyMass, metricType: "leanBodyMass",
            name: "Lean Body Mass", unit: { .gramUnit(with: .kilo) },
            displayUnit: "kg", category: .body, isCumulative: false,
            icon: "figure.strengthtraining.traditional", color: .brown,
            referenceMin: nil, referenceMax: nil,
            inputMin: 20, inputMax: 200, inputStep: 0.1,
            description: "Your body weight minus fat, including muscle, bone, and organs."
        ))

        list.append(Entry(
            identifier: .height, metricType: "height",
            name: "Height", unit: { .meterUnit(with: .centi) },
            displayUnit: "cm", category: .body, isCumulative: false,
            icon: "ruler", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 50, inputMax: 250, inputStep: 0.5,
            description: "Your standing height measurement."
        ))

        list.append(Entry(
            identifier: .waistCircumference, metricType: "waistCircumference",
            name: "Waist Circumference", unit: { .meterUnit(with: .centi) },
            displayUnit: "cm", category: .body, isCumulative: false,
            icon: "circle.dashed", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 40, inputMax: 200, inputStep: 0.5,
            description: "Circumference of your waist, an indicator of abdominal fat distribution."
        ))

        // ───────────────────────────────────────
        // RESPIRATORY
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .respiratoryRate, metricType: "respiratoryRate",
            name: "Respiratory Rate", unit: { .count().unitDivided(by: .minute()) },
            displayUnit: "br/min", category: .respiratory, isCumulative: false,
            icon: "wind", color: .teal,
            referenceMin: 12, referenceMax: 20,
            inputMin: 5, inputMax: 60, inputStep: 0.1,
            description: "Number of breaths taken per minute, typically measured during sleep by Apple Watch."
        ))

        list.append(Entry(
            identifier: .oxygenSaturation, metricType: "oxygenSaturation",
            name: "Blood Oxygen (SpO2)", unit: { .percent() },
            displayUnit: "%", category: .respiratory, isCumulative: false,
            icon: "drop.fill", color: .cyan,
            referenceMin: 95, referenceMax: 100,
            inputMin: 70, inputMax: 100, inputStep: 0.1,
            description: "Percentage of hemoglobin carrying oxygen in your blood, measured via wrist pulse oximetry."
        ))

        list.append(Entry(
            identifier: .forcedExpiratoryVolume1, metricType: "forcedExpiratoryVolume1",
            name: "FEV1", unit: { .liter() },
            displayUnit: "L", category: .respiratory, isCumulative: false,
            icon: "lungs", color: .teal,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 8, inputStep: 0.01,
            description: "Volume of air you can forcibly exhale in one second, a key lung function measure."
        ))

        list.append(Entry(
            identifier: .forcedVitalCapacity, metricType: "forcedVitalCapacity",
            name: "Forced Vital Capacity", unit: { .liter() },
            displayUnit: "L", category: .respiratory, isCumulative: false,
            icon: "lungs.fill", color: .teal,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 8, inputStep: 0.01,
            description: "Maximum volume of air you can exhale after a deep breath."
        ))

        list.append(Entry(
            identifier: .peakExpiratoryFlowRate, metricType: "peakExpiratoryFlowRate",
            name: "Peak Flow Rate", unit: { .liter().unitDivided(by: .minute()) },
            displayUnit: "L/min", category: .respiratory, isCumulative: false,
            icon: "wind", color: .cyan,
            referenceMin: nil, referenceMax: nil,
            inputMin: 50, inputMax: 900, inputStep: 5,
            description: "Maximum speed of airflow during a forced exhalation, used to monitor asthma."
        ))

        list.append(Entry(
            identifier: .inhalerUsage, metricType: "inhalerUsage",
            name: "Inhaler Usage", unit: { .count() },
            displayUnit: "puffs", category: .respiratory, isCumulative: true,
            icon: "allergens", color: .teal,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 50, inputStep: 1,
            description: "Number of inhaler puffs used, for tracking respiratory medication use."
        ))

        // ───────────────────────────────────────
        // NUTRITION
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .dietaryEnergyConsumed, metricType: "dietaryEnergyConsumed",
            name: "Calories Consumed", unit: { .kilocalorie() },
            displayUnit: "kcal", category: .nutrition, isCumulative: true,
            icon: "fork.knife", color: .brown,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 10000, inputStep: 10,
            description: "Total calories consumed from food and drink."
        ))

        list.append(Entry(
            identifier: .dietaryProtein, metricType: "dietaryProtein",
            name: "Protein", unit: { .gram() },
            displayUnit: "g", category: .nutrition, isCumulative: true,
            icon: "fish.fill", color: .red,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 500, inputStep: 1,
            description: "Grams of protein consumed, essential for muscle repair and growth."
        ))

        list.append(Entry(
            identifier: .dietaryCarbohydrates, metricType: "dietaryCarbohydrates",
            name: "Carbohydrates", unit: { .gram() },
            displayUnit: "g", category: .nutrition, isCumulative: true,
            icon: "leaf.fill", color: .yellow,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 1000, inputStep: 1,
            description: "Grams of carbohydrates consumed, your body's primary energy source."
        ))

        list.append(Entry(
            identifier: .dietaryFatTotal, metricType: "dietaryFatTotal",
            name: "Total Fat", unit: { .gram() },
            displayUnit: "g", category: .nutrition, isCumulative: true,
            icon: "drop.fill", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 500, inputStep: 1,
            description: "Total grams of fat consumed from all dietary sources."
        ))

        list.append(Entry(
            identifier: .dietarySugar, metricType: "dietarySugar",
            name: "Sugar", unit: { .gram() },
            displayUnit: "g", category: .nutrition, isCumulative: true,
            icon: "cube.fill", color: .pink,
            referenceMin: nil, referenceMax: 25,
            inputMin: 0, inputMax: 500, inputStep: 1,
            description: "Grams of sugar consumed; WHO recommends under 25g of added sugar daily."
        ))

        list.append(Entry(
            identifier: .dietaryFiber, metricType: "dietaryFiber",
            name: "Fiber", unit: { .gram() },
            displayUnit: "g", category: .nutrition, isCumulative: true,
            icon: "leaf", color: .green,
            referenceMin: 25, referenceMax: nil,
            inputMin: 0, inputMax: 200, inputStep: 1,
            description: "Grams of dietary fiber consumed, important for digestive health."
        ))

        list.append(Entry(
            identifier: .dietarySodium, metricType: "dietarySodium",
            name: "Sodium", unit: { .gramUnit(with: .milli) },
            displayUnit: "mg", category: .nutrition, isCumulative: true,
            icon: "drop.triangle.fill", color: .gray,
            referenceMin: nil, referenceMax: 2300,
            inputMin: 0, inputMax: 10000, inputStep: 10,
            description: "Milligrams of sodium consumed; excess intake is linked to high blood pressure."
        ))

        list.append(Entry(
            identifier: .dietaryWater, metricType: "dietaryWater",
            name: "Water Intake", unit: { .literUnit(with: .milli) },
            displayUnit: "mL", category: .nutrition, isCumulative: true,
            icon: "drop.fill", color: .blue,
            referenceMin: 2000, referenceMax: nil,
            inputMin: 0, inputMax: 10000, inputStep: 50,
            description: "Volume of water consumed; adequate hydration supports all body functions."
        ))

        list.append(Entry(
            identifier: .dietaryCaffeine, metricType: "dietaryCaffeine",
            name: "Caffeine", unit: { .gramUnit(with: .milli) },
            displayUnit: "mg", category: .nutrition, isCumulative: true,
            icon: "cup.and.saucer.fill", color: .brown,
            referenceMin: nil, referenceMax: 400,
            inputMin: 0, inputMax: 2000, inputStep: 10,
            description: "Milligrams of caffeine consumed; moderate intake is generally under 400mg daily."
        ))

        list.append(Entry(
            identifier: .dietaryVitaminD, metricType: "dietaryVitaminD",
            name: "Vitamin D", unit: { .gramUnit(with: .micro) },
            displayUnit: "mcg", category: .nutrition, isCumulative: true,
            icon: "sun.max.fill", color: .yellow,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 250, inputStep: 1,
            description: "Micrograms of vitamin D consumed, essential for bone health and immunity."
        ))

        list.append(Entry(
            identifier: .dietaryCalcium, metricType: "dietaryCalcium",
            name: "Calcium", unit: { .gramUnit(with: .milli) },
            displayUnit: "mg", category: .nutrition, isCumulative: true,
            icon: "bone.fill", color: .white,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 5000, inputStep: 10,
            description: "Milligrams of calcium consumed, vital for bones, teeth, and muscle function."
        ))

        list.append(Entry(
            identifier: .dietaryIron, metricType: "dietaryIron",
            name: "Iron", unit: { .gramUnit(with: .milli) },
            displayUnit: "mg", category: .nutrition, isCumulative: true,
            icon: "atom", color: .red,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100, inputStep: 1,
            description: "Milligrams of iron consumed, necessary for oxygen transport in blood."
        ))

        list.append(Entry(
            identifier: .dietaryPotassium, metricType: "dietaryPotassium",
            name: "Potassium", unit: { .gramUnit(with: .milli) },
            displayUnit: "mg", category: .nutrition, isCumulative: true,
            icon: "leaf.circle", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 10000, inputStep: 10,
            description: "Milligrams of potassium consumed, important for heart and muscle function."
        ))

        // ───────────────────────────────────────
        // MOBILITY
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .walkingSpeed, metricType: "walkingSpeed",
            name: "Walking Speed", unit: { .meter().unitDivided(by: .second()) },
            displayUnit: "m/s", category: .mobility, isCumulative: false,
            icon: "figure.walk", color: .mint,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 5, inputStep: 0.01,
            description: "Average speed while walking, reflecting overall mobility and fitness."
        ))

        list.append(Entry(
            identifier: .walkingStepLength, metricType: "walkingStepLength",
            name: "Step Length", unit: { .meterUnit(with: .centi) },
            displayUnit: "cm", category: .mobility, isCumulative: false,
            icon: "shoeprints.fill", color: .mint,
            referenceMin: nil, referenceMax: nil,
            inputMin: 20, inputMax: 120, inputStep: 0.5,
            description: "Average distance covered in a single step while walking."
        ))

        list.append(Entry(
            identifier: .walkingDoubleSupportPercentage, metricType: "walkingDoubleSupportPercentage",
            name: "Double Support Time", unit: { .percent() },
            displayUnit: "%", category: .mobility, isCumulative: false,
            icon: "figure.walk", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100, inputStep: 0.1,
            description: "Percentage of walking time with both feet on the ground, indicating stability."
        ))

        list.append(Entry(
            identifier: .walkingAsymmetryPercentage, metricType: "walkingAsymmetryPercentage",
            name: "Walking Asymmetry", unit: { .percent() },
            displayUnit: "%", category: .mobility, isCumulative: false,
            icon: "figure.walk", color: .orange,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100, inputStep: 0.1,
            description: "Difference in step time between left and right legs while walking."
        ))

        list.append(Entry(
            identifier: .stairAscentSpeed, metricType: "stairAscentSpeed",
            name: "Stair Ascent Speed", unit: { .meter().unitDivided(by: .second()) },
            displayUnit: "m/s", category: .mobility, isCumulative: false,
            icon: "figure.stairs", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 5, inputStep: 0.01,
            description: "Speed at which you climb stairs, measured in meters per second."
        ))

        list.append(Entry(
            identifier: .stairDescentSpeed, metricType: "stairDescentSpeed",
            name: "Stair Descent Speed", unit: { .meter().unitDivided(by: .second()) },
            displayUnit: "m/s", category: .mobility, isCumulative: false,
            icon: "figure.stairs", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 5, inputStep: 0.01,
            description: "Speed at which you descend stairs, measured in meters per second."
        ))

        list.append(Entry(
            identifier: .sixMinuteWalkTestDistance, metricType: "sixMinuteWalkTestDistance",
            name: "6-Min Walk Distance", unit: { .meter() },
            displayUnit: "m", category: .mobility, isCumulative: false,
            icon: "figure.walk.circle", color: .mint,
            referenceMin: 400, referenceMax: nil,
            inputMin: 0, inputMax: 1000, inputStep: 1,
            description: "Estimated distance you could walk in six minutes, a clinical fitness measure."
        ))

        list.append(Entry(
            identifier: .appleWalkingSteadiness, metricType: "appleWalkingSteadiness",
            name: "Walking Steadiness", unit: { .percent() },
            displayUnit: "%", category: .mobility, isCumulative: false,
            icon: "figure.walk.diamond", color: .green,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100, inputStep: 0.1,
            description: "Score reflecting your balance and stability while walking, from Apple Watch sensors."
        ))

        // ───────────────────────────────────────
        // OTHER
        // ───────────────────────────────────────

        list.append(Entry(
            identifier: .environmentalAudioExposure, metricType: "environmentalAudioExposure",
            name: "Environmental Sound", unit: { .decibelAWeightedSoundPressureLevel() },
            displayUnit: "dB", category: .other, isCumulative: false,
            icon: "ear.fill", color: .blue,
            referenceMin: nil, referenceMax: 80,
            inputMin: 0, inputMax: 150, inputStep: 1,
            description: "Average ambient sound level in your environment, measured in decibels."
        ))

        list.append(Entry(
            identifier: .headphoneAudioExposure, metricType: "headphoneAudioExposure",
            name: "Headphone Audio Level", unit: { .decibelAWeightedSoundPressureLevel() },
            displayUnit: "dB", category: .other, isCumulative: false,
            icon: "headphones", color: .purple,
            referenceMin: nil, referenceMax: 80,
            inputMin: 0, inputMax: 150, inputStep: 1,
            description: "Average audio level through headphones; prolonged exposure above 80dB may cause hearing damage."
        ))

        list.append(Entry(
            identifier: .numberOfTimesFallen, metricType: "numberOfTimesFallen",
            name: "Falls", unit: { .count() },
            displayUnit: "falls", category: .other, isCumulative: true,
            icon: "figure.fall", color: .red,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 50, inputStep: 1,
            description: "Number of detected falls, tracked by Apple Watch's fall detection feature."
        ))

        list.append(Entry(
            identifier: .numberOfAlcoholicBeverages, metricType: "numberOfAlcoholicBeverages",
            name: "Alcoholic Beverages", unit: { .count() },
            displayUnit: "drinks", category: .other, isCumulative: true,
            icon: "wineglass.fill", color: .purple,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 50, inputStep: 1,
            description: "Number of alcoholic drinks consumed."
        ))

        list.append(Entry(
            identifier: .uvExposure, metricType: "uvExposure",
            name: "UV Exposure", unit: { .count() },
            displayUnit: "UV index", category: .other, isCumulative: false,
            icon: "sun.max.trianglebadge.exclamationmark", color: .yellow,
            referenceMin: nil, referenceMax: 6,
            inputMin: 0, inputMax: 15, inputStep: 1,
            description: "UV radiation index exposure level; values above 6 indicate high sun intensity."
        ))

        list.append(Entry(
            identifier: .insulinDelivery, metricType: "insulinDelivery",
            name: "Insulin Delivery", unit: { .internationalUnit() },
            displayUnit: "IU", category: .other, isCumulative: true,
            icon: "syringe.fill", color: .blue,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 200, inputStep: 0.5,
            description: "Units of insulin delivered, tracked for diabetes management."
        ))

        list.append(Entry(
            identifier: .electrodermalActivity, metricType: "electrodermalActivity",
            name: "Electrodermal Activity", unit: { HKUnit(from: "mcS") },
            displayUnit: "μS", category: .other, isCumulative: false,
            icon: "hand.raised.fingers.spread.fill", color: .indigo,
            referenceMin: nil, referenceMax: nil,
            inputMin: 0, inputMax: 100, inputStep: 0.1,
            description: "Electrical conductance of the skin, which can reflect emotional arousal or stress."
        ))

        return list
    }()
}
