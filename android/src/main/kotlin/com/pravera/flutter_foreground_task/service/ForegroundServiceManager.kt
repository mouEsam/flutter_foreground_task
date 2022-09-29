package com.pravera.flutter_foreground_task.service

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.util.Log
import androidx.core.content.ContextCompat
import com.pravera.flutter_foreground_task.models.ForegroundServiceAction
import com.pravera.flutter_foreground_task.models.ForegroundServiceStatus
import com.pravera.flutter_foreground_task.models.ForegroundTaskOptions
import com.pravera.flutter_foreground_task.models.NotificationOptions

/**
 * A class that provides foreground service control and management functions.
 *
 * @author Dev-hwang
 * @version 1.0
 */
class ForegroundServiceManager {
	companion object {
		const val TAG = "ForegroundServiceM"
	}

	private var binder: ForegroundService.ForegroundBinder? = null
	private val  serviceConnection: ServiceConnection = object: ServiceConnection {
		override fun onServiceConnected(componentName: ComponentName, binder: IBinder) {
			Log.d(TAG, "Foreground service connected");
			if (binder is ForegroundService.ForegroundBinder) {
				this@ForegroundServiceManager.binder = binder
			}
		}

		override fun onServiceDisconnected(componentName: ComponentName) {
			Log.d(TAG, "Foreground service disconnected");
			binder = null
		}
	}

	private fun bindForegroundService(context: Context, intent: Intent) {
		context.bindService(
			intent,
			serviceConnection,
			Context.BIND_AUTO_CREATE
		)
	}

	private fun unbindForegroundService(context: Context) {
		context.unbindService(serviceConnection);
		binder = null
	}

	private fun createIntent(context: Context): Intent {
		return Intent(context, ForegroundService::class.java);
	}

	private fun startService(context: Context) {
		val nIntent = createIntent(context)
		val options = ForegroundTaskOptions.getData(context);
		if (!options.isBound) {
			ContextCompat.startForegroundService(context, nIntent)
		}
		bindForegroundService(context, nIntent)
	}

	fun bindActivity(context: Context) {
		if (isRunningService() && binder == null) {
			bindForegroundService(context, createIntent(context))
		}
	}

	fun unbindActivity(context: Context) {
		if (binder != null) {
			unbindForegroundService(context)
		}
	}

	/**
	 * Start the foreground service.
	 *
	 * @param context context
	 * @param arguments arguments
	 */
	fun start(context: Context, arguments: Map<*, *>?): Boolean {
		try {
			ForegroundServiceStatus.putData(context, ForegroundServiceAction.START)
			ForegroundTaskOptions.putData(context, arguments)
			NotificationOptions.putData(context, arguments)
			startService(context)
		} catch (e: Exception) {
			return false
		}

		return true
	}

	/**
	 * Restart the foreground service.
	 *
	 * @param context context
	 */
	fun restart(context: Context): Boolean {
		try {
			ForegroundServiceStatus.putData(context, ForegroundServiceAction.RESTART)
			if (binder == null) {
				startService(context)
			} else {
				binder?.restart()
			}
		} catch (e: Exception) {
			return false
		}
		return true
	}

	/**
	 * Update the foreground service.
	 *
	 * @param context context
	 * @param arguments arguments
	 */
	fun update(context: Context, arguments: Map<*, *>?): Boolean {
		try {
			ForegroundServiceStatus.putData(context, ForegroundServiceAction.UPDATE)
			ForegroundTaskOptions.updateCallbackHandle(context, arguments)
			NotificationOptions.updateContent(context, arguments)
			if (binder == null) {
				startService(context)
			} else {
				binder?.update()
			}
		} catch (e: Exception) {
			return false
		}
		return true
	}

	/**
	 * Stop the foreground service.
	 *
	 * @param context context
	 */
	fun stop(context: Context): Boolean {
		// If the service is not running, the stop function is not executed.
		if (!ForegroundService.isRunningService) return false
		try {
			ForegroundServiceStatus.putData(context, ForegroundServiceAction.STOP)
			ForegroundTaskOptions.clearData(context)
			NotificationOptions.clearData(context)
			if (binder == null) {
				val nIntent = createIntent(context)
				ContextCompat.startForegroundService(context, nIntent)
			} else {
				binder?.stop()
				unbindForegroundService(context)
			}
		} catch (e: Exception) {
			return false
		}

		return true
	}

	/** Returns whether the foreground service is running. */
	fun isRunningService(): Boolean = ForegroundService.isRunningService
}
