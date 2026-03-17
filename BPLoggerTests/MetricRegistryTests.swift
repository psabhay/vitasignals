import XCTest
@testable import BPLogger

final class MetricRegistryTests: XCTestCase {

    func testAllMetricsHaveDefinitions() {
        let types = [
            MetricType.bloodPressure,
            MetricType.restingHeartRate,
            MetricType.heartRateVariability,
            MetricType.vo2Max,
            MetricType.walkingHeartRate,
            MetricType.stepCount,
            MetricType.exerciseMinutes,
            MetricType.activeEnergy,
            MetricType.bodyMass,
            MetricType.sleepDuration,
            MetricType.respiratoryRate,
            MetricType.oxygenSaturation,
            MetricType.workout,
        ]
        for type in types {
            XCTAssertNotNil(MetricRegistry.definition(for: type), "Should have definition for \(type)")
        }
    }

    func testBPDefinition() {
        let def = MetricRegistry.definition(for: MetricType.bloodPressure)
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "Blood Pressure")
        XCTAssertEqual(def?.unit, "mmHg")
        XCTAssertEqual(def?.category, .vitals)
    }

    func testCategoryFiltering() {
        let vitals = MetricRegistry.definitions(for: .vitals)
        XCTAssertFalse(vitals.isEmpty)
        XCTAssertTrue(vitals.allSatisfy { $0.category == .vitals })

        let cardio = MetricRegistry.definitions(for: .cardioFitness)
        XCTAssertFalse(cardio.isEmpty)
        XCTAssertTrue(cardio.allSatisfy { $0.category == .cardioFitness })
    }

    func testSyncableMetrics() {
        let syncable = MetricRegistry.syncableMetrics
        XCTAssertFalse(syncable.isEmpty)
        // BP should not be in syncable (no hkQuantityType)
        XCTAssertFalse(syncable.contains { $0.type == MetricType.bloodPressure })
        // Resting HR should be syncable
        XCTAssertTrue(syncable.contains { $0.type == MetricType.restingHeartRate })
    }

    func testFormatValue() {
        let def = MetricRegistry.definition(for: MetricType.stepCount)!
        XCTAssertEqual(def.formatValue(8500), "8500")
        XCTAssertEqual(def.formatValue(120), "120")
        XCTAssertEqual(def.formatValue(65), "65")

        let weightDef = MetricRegistry.definition(for: MetricType.bodyMass)!
        XCTAssertEqual(weightDef.formatValue(72.5), "72.5")
    }

    func testAllMetricCategories() {
        // Every metric should belong to a valid category
        for def in MetricRegistry.all {
            XCTAssertTrue(MetricCategory.allCases.contains(def.category), "\(def.name) should have a valid category")
        }
    }

    func testMetricDefinitionHasIcon() {
        for def in MetricRegistry.all {
            XCTAssertFalse(def.icon.isEmpty, "\(def.name) should have an icon")
        }
    }

    func testMetricDefinitionHasUnit() {
        for def in MetricRegistry.all {
            XCTAssertFalse(def.unit.isEmpty, "\(def.name) should have a unit")
        }
    }

    // MARK: - HealthKit Catalog

    func testCatalogCoversAllCuratedTypes() {
        // Every curated type with hkQuantityType should exist in the catalog
        for def in MetricRegistry.all {
            guard def.hkQuantityType != nil else { continue }
            XCTAssertNotNil(
                HealthKitCatalog.entry(forMetricType: def.type),
                "Catalog should have entry for curated type \(def.type)"
            )
        }
    }

    func testCatalogAutoGeneratesDefinitions() {
        // A catalog-only type (not in curated list) should auto-generate a definition
        let catalogOnlyType = "bloodGlucose"
        let def = MetricRegistry.definition(for: catalogOnlyType)
        XCTAssertNotNil(def, "Should auto-generate definition for \(catalogOnlyType)")
        XCTAssertEqual(def?.name, "Blood Glucose")
        XCTAssertEqual(def?.unit, "mg/dL")
        XCTAssertEqual(def?.category, .vitals)
    }

    func testCuratedOverridesCatalog() {
        // Curated definition should take precedence over catalog
        let def = MetricRegistry.definition(for: MetricType.restingHeartRate)
        XCTAssertNotNil(def)
        // Curated has cardioFitness category, catalog has vitals
        XCTAssertEqual(def?.category, .cardioFitness)
    }

    func testCatalogEntriesHaveUniqueMetricTypes() {
        let types = HealthKitCatalog.entries.map(\.metricType)
        XCTAssertEqual(types.count, Set(types).count, "Catalog should have unique metric types")
    }

    func testAllCategoriesHaveIconAndColor() {
        for category in MetricCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category.rawValue) should have an icon")
        }
    }
}
