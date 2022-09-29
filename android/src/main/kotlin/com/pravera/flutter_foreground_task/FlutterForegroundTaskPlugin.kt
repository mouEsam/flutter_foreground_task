package com.pravera.flutter_foreground_task

import android.util.Log
import com.pravera.flutter_foreground_task.service.ForegroundServiceManager
import com.pravera.flutter_foreground_task.service.ServiceProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/** FlutterForegroundTaskPlugin */
class FlutterForegroundTaskPlugin : FlutterPlugin, ActivityAware, ServiceProvider {

    companion object {
        const val TAG = "FlutterForegroundT"
        var foregroundServiceManager: ForegroundServiceManager = ForegroundServiceManager()
    }

    private var activityBinding: ActivityPluginBinding? = null
    private lateinit var methodCallHandler: MethodCallHandlerImpl

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine ${binding.flutterEngine.hashCode()}")
        methodCallHandler = MethodCallHandlerImpl(binding.applicationContext, this)
        methodCallHandler.init(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine ${binding.flutterEngine.hashCode()}")
        if (::methodCallHandler.isInitialized) {
            methodCallHandler.dispose()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.d(TAG, "onAttachedToActivity")
        attachedToActivity(binding, configChanges = false)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.d(TAG, "onReattachedToActivityForConfigChanges")
        attachedToActivity(binding, configChanges = true)
    }

    private fun attachedToActivity(binding: ActivityPluginBinding, configChanges: Boolean) {
        Log.d(TAG, "onAttachedToActivity")
        methodCallHandler.setActivity(binding.activity)
        binding.addActivityResultListener(methodCallHandler)
        activityBinding = binding
        if (!configChanges) {
            foregroundServiceManager.bindActivity(binding.activity.applicationContext)
        }
    }

    override fun onDetachedFromActivity() {
        Log.d(TAG, "onDetachedFromActivity")
        detachedFromActivity(configChanges = false)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "onDetachedFromActivityForConfigChanges")
        detachedFromActivity(configChanges = true)
    }

    private fun detachedFromActivity(configChanges: Boolean) {
        activityBinding?.run {
            if (!configChanges) {
                foregroundServiceManager.unbindActivity(activity.applicationContext)
            }
            removeActivityResultListener(methodCallHandler)
        }
        activityBinding = null
        methodCallHandler.setActivity(null)
    }

    override fun getForegroundServiceManager() = foregroundServiceManager
}
