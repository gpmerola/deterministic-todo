package app.deterministic.todo.runtracker

import android.content.Context
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
    fun refreshToday(context: Context, callback: Callback) {
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
                val zone = ZoneId.systemDefault()
                val day = LocalDate.now(zone)
                val start = day.atStartOfDay(zone).toInstant()
                val end = minOf(Instant.now(), day.plusDays(1).atStartOfDay(zone).toInstant())
                val result = client.aggregate(
                    AggregateRequest(
                        metrics = setOf(StepsRecord.COUNT_TOTAL),
                        timeRangeFilter = TimeRangeFilter.between(start, end)
                    )
                )
                val steps = result[StepsRecord.COUNT_TOTAL] ?: 0L
                val preferences = appContext.getSharedPreferences("movement_profile", Context.MODE_PRIVATE)
                val stride = preferences.getFloat("walking_stride_meters", MovementEstimate.DEFAULT_STRIDE_METERS.toFloat()).toDouble()
                val weight = preferences.getFloat("weight_kg", MovementEstimate.DEFAULT_WEIGHT_KG.toFloat()).toDouble()
                val estimate = MovementEstimate.fromSteps(steps, stride, weight)
                val row = DailyMovement().apply {
                    this.day = day.toString()
                    zoneId = zone.id
                    source = "health_connect_aggregate"
                    this.steps = estimate.steps()
                    estimatedDistanceMeters = estimate.distanceMeters()
                    estimatedActiveCalories = estimate.activeCalories()
                    updatedAtMillis = System.currentTimeMillis()
                }
                RunDatabase.get(appContext).runs().upsertDailyMovement(row)
                withContext(Dispatchers.Main) { callback.onSuccess(row) }
            } catch (_: SecurityException) {
                withContext(Dispatchers.Main) { callback.onPermissionRequired() }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { callback.onError() }
            }
        }
    }

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
                    withContext(Dispatchers.Main) { callback.onError() }
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
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { callback.onError() }
            }
        }
    }

    data class GoogleFitComparison(
        val steps: Long?,
        val distanceMeters: Double?,
        val activeCalories: Double?,
        val localDistanceMeters: Double,
        val localSteps: Long,
        val durationMillis: Long
    )

    interface ComparisonCallback {
        fun onSuccess(comparison: GoogleFitComparison)
        fun onPermissionRequired()
        fun onUnavailable()
        fun onError()
    }

    interface Callback {
        fun onSuccess(movement: DailyMovement)
        fun onPermissionRequired()
        fun onUnavailable()
        fun onError()
    }
}
