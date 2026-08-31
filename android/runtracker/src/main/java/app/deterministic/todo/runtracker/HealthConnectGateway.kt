package app.deterministic.todo.runtracker

import android.content.Context
import android.os.SystemClock
import androidx.activity.result.contract.ActivityResultContract
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

object HealthConnectGateway {
    const val AVAILABLE = HealthConnectClient.SDK_AVAILABLE
    private const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @JvmStatic
    fun sdkStatus(context: Context): Int =
        HealthConnectClient.getSdkStatus(context, PROVIDER_PACKAGE)

    @JvmStatic
    fun permissions(context: Context): Set<String> {
        val result = mutableSetOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)
        )
        if (sdkStatus(context) == AVAILABLE) {
            val client = HealthConnectClient.getOrCreate(context.applicationContext, PROVIDER_PACKAGE)
            if (client.features.getFeatureStatus(
                    HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND
                ) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
            ) result.add(HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)
        }
        return result
    }

    @JvmStatic
    fun permissionContract(): ActivityResultContract<Set<String>, Set<String>> =
        PermissionController.createRequestPermissionResultContract(PROVIDER_PACKAGE)

    @JvmStatic
    fun compareGoogleFit(context: Context, session: RunSession, callback: ComparisonCallback) {
        if (sdkStatus(context) != AVAILABLE) {
            callback.onUnavailable()
            return
        }
        val appContext = context.applicationContext
        scope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(appContext, PROVIDER_PACKAGE)
                if (!client.permissionController.getGrantedPermissions().containsAll(permissions(appContext))) {
                    withContext(Dispatchers.Main) { callback.onPermissionRequired() }
                    return@launch
                }
                val endedAt = session.endedAtMillis ?: run {
                    withContext(Dispatchers.Main) { callback.onError("health_error_incomplete_session") }
                    return@launch
                }
                val result = client.aggregate(
                    AggregateRequest(
                        metrics = setOf(
                            StepsRecord.COUNT_TOTAL,
                            DistanceRecord.DISTANCE_TOTAL,
                            ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL
                        ),
                        timeRangeFilter = TimeRangeFilter.between(
                            Instant.ofEpochMilli(session.startedAtMillis),
                            Instant.ofEpochMilli(endedAt)
                        ),
                        dataOriginFilter = setOf(DataOrigin("com.google.android.apps.fitness"))
                    )
                )
                val comparison = GoogleFitComparison(
                    result[StepsRecord.COUNT_TOTAL],
                    result[DistanceRecord.DISTANCE_TOTAL]?.inMeters,
                    result[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories,
                    session.distanceMeters,
                    DriveTestExportManager.directSteps(appContext, session.id),
                    endedAt - session.startedAtMillis
                )
                withContext(Dispatchers.Main) { callback.onSuccess(comparison) }
            } catch (_: SecurityException) {
                withContext(Dispatchers.Main) { callback.onPermissionRequired() }
            } catch (error: Exception) {
                val code = "health_error_" + error.javaClass.simpleName.ifEmpty { "Exception" }
                withContext(Dispatchers.Main) { callback.onError(code) }
            }
        }
    }

    @JvmStatic
    fun auditDay(context: Context, day: LocalDate, callback: AuditCallback) {
        if (sdkStatus(context) != AVAILABLE) {
            callback.onError("unavailable")
            return
        }
        val appContext = context.applicationContext
        scope.launch {
            val auditStarted = SystemClock.elapsedRealtime()
            try {
                val client = HealthConnectClient.getOrCreate(appContext, PROVIDER_PACKAGE)
                if (!client.permissionController.getGrantedPermissions().containsAll(permissions(appContext))) {
                    withContext(Dispatchers.Main) { callback.onError("permission_required") }
                    return@launch
                }
                val zone = ZoneId.systemDefault()
                val start = day.atStartOfDay(zone).toInstant()
                val dayEnd = day.plusDays(1).atStartOfDay(zone).toInstant()
                val end = minOf(Instant.now(), dayEnd).coerceAtLeast(start)
                val metrics = setOf(
                    StepsRecord.COUNT_TOTAL,
                    DistanceRecord.DISTANCE_TOTAL,
                    ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL
                )
                val local = PhoneDailyMovementGateway.totalsForDay(appContext, day, zone)
                val fitStarted = SystemClock.elapsedRealtime()
                val fit = client.aggregate(AggregateRequest(
                    metrics = metrics,
                    timeRangeFilter = TimeRangeFilter.between(start, end),
                    dataOriginFilter = setOf(DataOrigin("com.google.android.apps.fitness"))
                ))
                val fitAggregateDuration = SystemClock.elapsedRealtime() - fitStarted
                val classificationStarted = SystemClock.elapsedRealtime()
                val fitSteps = fit[StepsRecord.COUNT_TOTAL]
                val classified = classifySteps(appContext, client, start, end,
                    fitSteps ?: 0L)
                val classificationDuration = SystemClock.elapsedRealtime() - classificationStarted
                val value = PassiveAudit(
                    day.toString(), zone.id, start.toEpochMilli(), end.toEpochMilli(),
                    local.fusedSteps,
                    null,
                    null,
                    fitSteps,
                    fit[DistanceRecord.DISTANCE_TOTAL]?.inMeters,
                    fit[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories,
                    0, 0, local.fusedSteps, 0, 0, 0, 0,
                    classified.rawRecordCount, classified.rawRecordSteps,
                    classified.invalidIntervalRecords, classified.googleFitRecordCount,
                    classified.googleFitRawSteps, classified.otherRecordCount,
                    classified.earliestRecordStartMillis, classified.latestRecordEndMillis,
                    classified.walkingDurationMillis, classified.runningDurationMillis,
                    classified.unknownDurationMillis, classified.vehicleDurationMillis,
                    classified.bicycleDurationMillis, classified.stillDurationMillis,
                    classified.exclusionThresholdRecordCount,
                    classified.observedStepsBeforeReconciliation,
                    classified.walkingStepsBeforeReconciliation,
                    classified.runningStepsBeforeReconciliation,
                    classified.unknownStepsBeforeReconciliation,
                    classified.vehicleStepsBeforeReconciliation,
                    classified.bicycleStepsBeforeReconciliation,
                    classified.stillConflictStepsBeforeReconciliation,
                    classified.reconciliationScaleFactor,
                    classified.minuteTimeline,
                    0, fitAggregateDuration, classificationDuration,
                    local.phoneSteps, local.bipSteps, local.fusionSource,
                    local.phoneObserved,
                    SystemClock.elapsedRealtime() - auditStarted
                )
                withContext(Dispatchers.Main) { callback.onSuccess(value) }
            } catch (error: SecurityException) {
                withContext(Dispatchers.Main) { callback.onError("permission_required") }
            } catch (error: Exception) {
                val code = "health_error_" + error.javaClass.simpleName.ifEmpty { "Exception" }
                withContext(Dispatchers.Main) { callback.onError(code) }
            }
        }
    }

    private suspend fun classifySteps(context: Context, client: HealthConnectClient,
                                      start: Instant, end: Instant,
                                      aggregateSteps: Long): ClassifiedSteps {
        val timeline = ActivityTimeline.read(context)
        var walking = 0L
        var running = 0L
        var unknown = 0L
        var vehicle = 0L
        var bicycle = 0L
        var stillConflict = 0L
        var walkingDuration = 0L
        var runningDuration = 0L
        var unknownDuration = 0L
        var vehicleDuration = 0L
        var bicycleDuration = 0L
        var stillDuration = 0L
        var rawRecordCount = 0
        var rawRecordSteps = 0L
        var invalidIntervalRecords = 0
        var googleFitRecordCount = 0
        var googleFitRawSteps = 0L
        var otherRecordCount = 0
        var earliestRecordStartMillis: Long? = null
        var latestRecordEndMillis: Long? = null
        var exclusionThresholdRecordCount = 0
        val minuteTimeline = PassiveMinuteTimeline.Builder()
        var token: String? = null
        do {
            val response = client.readRecords(ReadRecordsRequest(
                recordType = StepsRecord::class,
                timeRangeFilter = TimeRangeFilter.between(start, end),
                dataOriginFilter = setOf(DataOrigin("com.google.android.apps.fitness")),
                pageToken = token
            ))
            for (record in response.records) {
                rawRecordCount++
                rawRecordSteps += record.count
                val recordStart = record.startTime.toEpochMilli()
                val recordEnd = record.endTime.toEpochMilli()
                if (recordEnd <= recordStart) invalidIntervalRecords++
                earliestRecordStartMillis = minOf(earliestRecordStartMillis ?: recordStart, recordStart)
                latestRecordEndMillis = maxOf(latestRecordEndMillis ?: recordEnd, recordEnd)
                if (record.metadata.dataOrigin.packageName == "com.google.android.apps.fitness") {
                    googleFitRecordCount++
                    googleFitRawSteps += record.count
                } else otherRecordCount++
                val allocation = StepIntervalClassifier.classify(
                    recordStart, recordEnd,
                    record.count, timeline)
                minuteTimeline.addSteps(recordStart, recordEnd, record.count,
                    record.metadata.dataOrigin.packageName == "com.google.android.apps.fitness",
                    timeline)
                walking += allocation.walking()
                running += allocation.running()
                unknown += allocation.unknown()
                vehicle += allocation.vehicle()
                bicycle += allocation.bicycle()
                stillConflict += allocation.stillConflict()
                walkingDuration += allocation.walkingDurationMillis()
                runningDuration += allocation.runningDurationMillis()
                unknownDuration += allocation.unknownDurationMillis()
                vehicleDuration += allocation.vehicleDurationMillis()
                bicycleDuration += allocation.bicycleDurationMillis()
                stillDuration += allocation.stillDurationMillis()
                if (allocation.exclusionThresholdApplied()) exclusionThresholdRecordCount++
            }
            token = response.pageToken
        } while (token != null)
        var distanceToken: String? = null
        do {
            val response = client.readRecords(ReadRecordsRequest(
                recordType = DistanceRecord::class,
                timeRangeFilter = TimeRangeFilter.between(start, end),
                dataOriginFilter = setOf(DataOrigin("com.google.android.apps.fitness")),
                pageToken = distanceToken
            ))
            for (record in response.records) {
                if (record.metadata.dataOrigin.packageName == "com.google.android.apps.fitness") {
                    minuteTimeline.addFitDistance(record.startTime.toEpochMilli(),
                        record.endTime.toEpochMilli(), record.distance.inMeters)
                }
            }
            distanceToken = response.pageToken
        } while (distanceToken != null)
        val observed = walking + running + unknown + vehicle + bicycle + stillConflict
        if (observed <= 0 || aggregateSteps <= 0) return ClassifiedSteps(
            0, 0, aggregateSteps, 0, 0, 0, 0,
            rawRecordCount, rawRecordSteps, invalidIntervalRecords,
            googleFitRecordCount, googleFitRawSteps, otherRecordCount,
            earliestRecordStartMillis, latestRecordEndMillis,
            walkingDuration, runningDuration, unknownDuration, vehicleDuration,
            bicycleDuration, stillDuration, exclusionThresholdRecordCount,
            observed, walking, running, unknown, vehicle, bicycle, stillConflict,
            if (observed > 0) aggregateSteps.toDouble() / observed else 0.0,
            minuteTimeline.buildReferenceOnly())
        fun scaled(value: Long) = (value.toDouble() * aggregateSteps / observed).toLong()
        val scaledWalking = scaled(walking)
        val scaledRunning = scaled(running)
        val scaledVehicle = scaled(vehicle)
        val scaledBicycle = scaled(bicycle)
        val scaledStillConflict = scaled(stillConflict)
        val genericUnknown = (aggregateSteps - scaledWalking - scaledRunning - scaledVehicle -
            scaledBicycle - scaledStillConflict)
            .coerceAtLeast(0)
        return ClassifiedSteps(scaledWalking, scaledRunning,
            genericUnknown + scaledStillConflict, scaledVehicle + scaledBicycle,
            scaledVehicle, scaledBicycle, scaledStillConflict,
            rawRecordCount, rawRecordSteps, invalidIntervalRecords,
            googleFitRecordCount, googleFitRawSteps, otherRecordCount,
            earliestRecordStartMillis, latestRecordEndMillis,
            walkingDuration, runningDuration, unknownDuration, vehicleDuration,
            bicycleDuration, stillDuration, exclusionThresholdRecordCount,
            observed, walking, running, unknown, vehicle, bicycle, stillConflict,
            aggregateSteps.toDouble() / observed, minuteTimeline.buildReferenceOnly())
    }

    private data class ClassifiedSteps(val walkingSteps: Long, val runningSteps: Long,
        val unknownSteps: Long, val excludedSteps: Long, val vehicleSteps: Long,
        val bicycleSteps: Long, val stillConflictSteps: Long,
        val rawRecordCount: Int, val rawRecordSteps: Long,
        val invalidIntervalRecords: Int, val googleFitRecordCount: Int,
        val googleFitRawSteps: Long, val otherRecordCount: Int,
        val earliestRecordStartMillis: Long?, val latestRecordEndMillis: Long?,
        val walkingDurationMillis: Long, val runningDurationMillis: Long,
        val unknownDurationMillis: Long, val vehicleDurationMillis: Long,
        val bicycleDurationMillis: Long, val stillDurationMillis: Long,
        val exclusionThresholdRecordCount: Int,
        val observedStepsBeforeReconciliation: Long,
        val walkingStepsBeforeReconciliation: Long,
        val runningStepsBeforeReconciliation: Long,
        val unknownStepsBeforeReconciliation: Long,
        val vehicleStepsBeforeReconciliation: Long,
        val bicycleStepsBeforeReconciliation: Long,
        val stillConflictStepsBeforeReconciliation: Long,
        val reconciliationScaleFactor: Double,
        val minuteTimeline: List<PassiveMinuteTimeline.Minute>)

    data class GoogleFitComparison(
        val steps: Long?,
        val distanceMeters: Double?,
        val activeCalories: Double?,
        val localDistanceMeters: Double,
        val localSteps: Long,
        val durationMillis: Long
    )

    data class PassiveAudit(
        val day: String,
        val zoneId: String,
        val intervalStartMillis: Long,
        val intervalEndMillis: Long,
        val allSteps: Long,
        val allDistanceMeters: Double?,
        val allActiveCalories: Double?,
        val fitSteps: Long?,
        val fitDistanceMeters: Double?,
        val fitActiveCalories: Double?,
        val walkingSteps: Long,
        val runningSteps: Long,
        val unknownSteps: Long,
        val excludedSteps: Long,
        val vehicleSteps: Long,
        val bicycleSteps: Long,
        val stillConflictSteps: Long,
        val rawStepRecordCount: Int,
        val rawStepRecordSteps: Long,
        val invalidStepIntervalRecords: Int,
        val googleFitStepRecordCount: Int,
        val googleFitRawRecordSteps: Long,
        val otherStepRecordCount: Int,
        val earliestStepRecordStartMillis: Long?,
        val latestStepRecordEndMillis: Long?,
        val walkingRecordDurationMillis: Long,
        val runningRecordDurationMillis: Long,
        val unknownRecordDurationMillis: Long,
        val vehicleRecordDurationMillis: Long,
        val bicycleRecordDurationMillis: Long,
        val stillRecordDurationMillis: Long,
        val exclusionThresholdRecordCount: Int,
        val observedStepsBeforeReconciliation: Long,
        val walkingStepsBeforeReconciliation: Long,
        val runningStepsBeforeReconciliation: Long,
        val unknownStepsBeforeReconciliation: Long,
        val vehicleStepsBeforeReconciliation: Long,
        val bicycleStepsBeforeReconciliation: Long,
        val stillConflictStepsBeforeReconciliation: Long,
        val reconciliationScaleFactor: Double,
        val minuteTimeline: List<PassiveMinuteTimeline.Minute>,
        val allSourcesAggregateDurationMillis: Long,
        val googleFitAggregateDurationMillis: Long,
        val classificationDurationMillis: Long,
        val phoneSteps: Long,
        val bipSteps: Long,
        val fusionSource: String,
        val phoneObserved: Boolean,
        val totalReadDurationMillis: Long
    )

    interface AuditCallback {
        fun onSuccess(audit: PassiveAudit)
        fun onError(code: String)
    }

    interface ComparisonCallback {
        fun onSuccess(comparison: GoogleFitComparison)
        fun onPermissionRequired()
        fun onUnavailable()
        fun onError(code: String)
    }

}
