package com.bubaa.mura

import android.app.PendingIntent
import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.widget.RemoteViews
import org.json.JSONArray

class MotionQuoteWidgetProvider : AppWidgetProvider() {
    override fun onEnabled(context: Context) {
        scheduleUpdates(context)
    }

    override fun onDisabled(context: Context) {
        cancelUpdates(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            updateAll(context)
            scheduleUpdates(context)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        scheduleUpdates(context)
        updateAll(context)
    }

    companion object {
        private const val ACTION_REFRESH = "com.bubaa.mura.MOTION_QUOTE_REFRESH"
        private const val REQUEST_CODE = 2407
        private const val REFRESH_INTERVAL_MS = 30_000L

        private fun refreshIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                Intent(context, MotionQuoteWidgetProvider::class.java)
                    .setAction(ACTION_REFRESH),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        private fun scheduleUpdates(context: Context) {
            context.getSystemService(AlarmManager::class.java).setRepeating(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + REFRESH_INTERVAL_MS,
                REFRESH_INTERVAL_MS,
                refreshIntent(context),
            )
        }

        private fun cancelUpdates(context: Context) {
            context.getSystemService(AlarmManager::class.java)
                .cancel(refreshIntent(context))
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = android.content.ComponentName(context, MotionQuoteWidgetProvider::class.java)
            val prefs = context.getSharedPreferences("motion_quote", Context.MODE_PRIVATE)
            val texts = runCatching {
                JSONArray(prefs.getString("texts", "[]").orEmpty())
            }.getOrElse { JSONArray() }
            val sources = runCatching {
                JSONArray(prefs.getString("sources", "[]").orEmpty())
            }.getOrElse { JSONArray() }
            val fallbackText =
                "Whatever the mind of man can conceive and believe, it can achieve."
            val fallbackSource = "Napoleon Hill"
            val count = texts.length()
            val index = if (count == 0) 0 else {
                ((System.currentTimeMillis() / REFRESH_INTERVAL_MS) % count).toInt()
            }
            val text = if (count == 0) fallbackText else texts.optString(index, fallbackText)
            val source = if (count == 0) fallbackSource else sources.optString(index, fallbackSource)
            manager.getAppWidgetIds(component).forEach { id ->
                val views = RemoteViews(context.packageName, R.layout.motion_quote_widget)
                views.setTextViewText(R.id.motion_quote_text, text)
                views.setTextViewText(R.id.motion_quote_source, source)
                val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (intent != null) {
                    views.setOnClickPendingIntent(
                        R.id.motion_quote_widget_root,
                        PendingIntent.getActivity(
                            context,
                            0,
                            intent,
                            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                        ),
                    )
                }
                manager.updateAppWidget(id, views)
            }
        }
    }
}
