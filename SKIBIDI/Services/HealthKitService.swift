import Foundation
import HealthKit

/// Reads the current device user's health data from HealthKit and folds it into a
/// `HealthSnapshot`. Only ever returns the device owner's data — other members stay mock.
///
/// Mirrors LatestMap's `HealthService` boundary, but implemented against a real `HKHealthStore`
/// (LatestMap left the real read as a TODO). Gracefully degrades to the supplied mock snapshot
/// when HealthKit is unavailable or unauthorized, so the UI always has values to show.
@MainActor
final class HealthKitService {
    private let store = HKHealthStore()

    /// Live step-count observer; held so we can stop it when updates are no longer needed.
    private var stepObserverQuery: HKObserverQuery?

    /// HealthKit is unavailable on some devices (e.g. iPad); callers fall back to mock data.
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Read-only quantity/category types backing the snapshot fields we surface.
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let restingHR = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(restingHR) }
        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(exercise) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let resp = HKObjectType.quantityType(forIdentifier: .respiratoryRate) { types.insert(resp) }
    
        return types
    }

    /// Requests read authorization. Returns `true` when the prompt completed without error
    /// (note: HealthKit never reveals whether the user actually granted read access).
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            print("HealthKit authorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Reads today's metrics (and last night's sleep) and returns `base` with the live values
    /// merged in. Fields HealthKit can't supply (goals) are kept from `base`, so the
    /// snapshot — and its derived `energyScore` — stays coherent.
    func fetchTodaySnapshot(merging base: HealthSnapshot) async -> HealthSnapshot {
        guard isAvailable else { return base }
        var snapshot = base

        async let stepsValue = sumToday(.stepCount, unit: .count())
        async let distanceValue = sumToday(.distanceWalkingRunning, unit: .meter())
        async let energyValue = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let exerciseValue = sumToday(.appleExerciseTime, unit: .minute())
        async let restingHRValue = mostRecent(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let sleepValue = sleepHoursLastNight()
        async let hrvValue = mostRecent(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let respValue = mostRecent(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()))

        if let steps = await stepsValue { snapshot.steps = Int(steps) }
        if let distance = await distanceValue { snapshot.stepsDistanceKm = (distance / 1000).rounded(toPlaces: 1) }
        if let energy = await energyValue {
            snapshot.activeCalories = Int(energy)
            snapshot.moveCalories = Int(energy)
        }
        if let exercise = await exerciseValue { snapshot.exerciseMinutes = Int(exercise) }
        if let hr = await restingHRValue { snapshot.restingHeartRate = Int(hr) }
        if let sleep = await sleepValue { snapshot.sleepHours = sleep.rounded(toPlaces: 1) }
        // 0 is the model's "unavailable" sentinel — missing HRV/respiratory samples must not
        // inherit stale values from `base`, or the recovery composite would count them as real.
        snapshot.hrv = (await hrvValue) ?? 0
        snapshot.respiratoryRate = (await respValue) ?? 0

        return snapshot
    }

    // MARK: - Live updates

    /// Starts a HealthKit observer that fires `onChange` whenever new step samples are written
    /// (e.g. as the user keeps walking), so the UI can refresh without relaunching the app.
    /// Safe to call repeatedly — any existing observer is stopped first.
    func startStepUpdates(_ onChange: @escaping @MainActor () -> Void) {
        guard isAvailable,
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }

        stopStepUpdates()

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { _, completionHandler, error in
            if error == nil {
                Task { @MainActor in onChange() }
            }
            // Let HealthKit know we've handled this update.
            completionHandler()
        }
        store.execute(query)
        stepObserverQuery = query
    }

    /// Stops the live step observer (call from `onDisappear`).
    func stopStepUpdates() {
        if let query = stepObserverQuery {
            store.stop(query)
            stepObserverQuery = nil
        }
    }

    // MARK: - Query helpers

    /// Sum of a cumulative quantity (steps, distance, energy, exercise minutes) since midnight.
    private func sumToday(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Most recent sample of a discrete quantity (e.g. resting heart rate).
    private func mostRecent(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Total "asleep" hours from samples ending in the last 24h (covers last night).
    private func sleepHoursLastNight() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                // Sum any "asleep" stage (core/deep/REM on iOS 16+, plus the legacy `.asleep`).
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let seconds = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }
}

private extension Double {
    /// Rounds to `places` decimal places (used to keep distance/sleep tidy for display).
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
