package app.deterministic.todo.deterministic_todo

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var updateManager: AppUpdateManager
    private val installListener = InstallStateUpdatedListener { state ->
        if (state.installStatus() == InstallStatus.DOWNLOADED) {
            updateManager.completeUpdate()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RunTrackerChannel.register(this, flutterEngine)
        updateManager = AppUpdateManagerFactory.create(this)
        updateManager.registerListener(installListener)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.deterministic.todo/play_update",
        ).setMethodCallHandler { call, result ->
            if (call.method != "checkUpdate") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            checkForUpdate(
                call.argument<Boolean>("startIfAvailable") ?: false,
                result,
            )
        }
    }

    private fun checkForUpdate(startIfAvailable: Boolean, result: MethodChannel.Result) {
        updateManager.appUpdateInfo
            .addOnSuccessListener { info ->
                if (info.installStatus() == InstallStatus.DOWNLOADED) {
                    updateManager.completeUpdate()
                    result.success(mapOf("status" to "started"))
                    return@addOnSuccessListener
                }
                if (info.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE) {
                    result.success(mapOf("status" to "unavailable"))
                    return@addOnSuccessListener
                }
                val options = AppUpdateOptions.defaultOptions(AppUpdateType.FLEXIBLE)
                if (!startIfAvailable || !info.isUpdateTypeAllowed(options)) {
                    result.success(mapOf("status" to "available"))
                    return@addOnSuccessListener
                }
                updateManager.startUpdateFlow(info, this, options)
                    .addOnSuccessListener { resultCode ->
                        result.success(
                            mapOf(
                                "status" to if (resultCode == Activity.RESULT_OK) {
                                    "started"
                                } else {
                                    "available"
                                },
                            ),
                        )
                    }
                    .addOnFailureListener {
                        result.success(mapOf("status" to "error"))
                    }
            }
            .addOnFailureListener {
                result.success(mapOf("status" to "error"))
            }
    }

    override fun onDestroy() {
        if (::updateManager.isInitialized) {
            updateManager.unregisterListener(installListener)
        }
        super.onDestroy()
    }
}
