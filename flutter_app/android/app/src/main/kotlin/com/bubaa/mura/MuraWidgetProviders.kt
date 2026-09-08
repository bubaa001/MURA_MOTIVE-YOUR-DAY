package com.bubaa.mura

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray

/**
 * Shared data + helpers for the MURA widget family. The Flutter app pushes
 * fresh data through the "widgets" channel into prefs; providers render it.
 */
object MuraWidgets {
    private fun prefs(context: Context) =
        context.getSharedPreferences("mura_widgets", Context.MODE_PRIVATE)

    fun text(context: Context, key: String, fallback: String): String =
        prefs(context).getString(key, null) ?: fallback

    fun stringList(context: Context, key: String): List<String> = runCatching {
        val arr = JSONArray(prefs(context).getString(key, "[]").orEmpty())
        (0 until arr.length()).map { arr.optString(it) }
    }.getOrDefault(emptyList())

    fun clickThrough(context: Context, views: RemoteViews, rootId: Int) {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (intent != null) {
            views.setOnClickPendingIntent(
                rootId,
                PendingIntent.getActivity(
                    context, 0, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        }
    }

    fun update(context: Context, provider: Class<*>, layout: Int, build: (RemoteViews) -> Unit) {
        val manager = AppWidgetManager.getInstance(context)
        val component = ComponentName(context, provider)
        manager.getAppWidgetIds(component).forEach { id ->
            val views = RemoteViews(context.packageName, layout)
            build(views)
            manager.updateAppWidget(id, views)
        }
    }
}

/** Today's quote - wide banner card; quote and source cross-fade in a flipper. */
class QuoteWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        renderAll(context)
    }
    companion object {
        fun renderAll(context: Context) {
            val quote = MuraWidgets.text(context, "quote", "Whatever the mind of man can conceive and believe, it can achieve.")
            val source = MuraWidgets.text(context, "quote_source", "Napoleon Hill")
            MuraWidgets.update(context, QuoteWidgetProvider::class.java, R.layout.quote_widget) { v ->
                v.setTextViewText(R.id.quote_text, quote)
                // Frame 1 of the flipper: "— Napoleon Hill" gets its own quiet moment.
                v.setTextViewText(R.id.quote_source, "— $source")
                MuraWidgets.clickThrough(context, v, R.id.quote_root)
            }
        }
    }
}

/** Current streak - compact square with a bar toward the next milestone. */
class StreakWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        renderAll(context)
    }
    companion object {
        private val MILESTONES = intArrayOf(3, 7, 14, 30, 60, 100, 365)

        fun renderAll(context: Context) {
            val days = MuraWidgets.text(context, "streak", "0").toIntOrNull() ?: 0
            val label = MuraWidgets.text(context, "streak_label", "DAY STREAK")
            // Next milestone strictly above the current streak.
            val next = MILESTONES.firstOrNull { it > days }
            val (progress, hint) = when (next) {
                null -> 100 to "All milestones conquered"
                else -> {
                    val prev = MILESTONES.lastOrNull { it <= days } ?: 0
                    val pct = ((days - prev) * 100) / (next - prev)
                    pct to "$days / $next days"
                }
            }
            MuraWidgets.update(context, StreakWidgetProvider::class.java, R.layout.streak_widget) { v ->
                v.setTextViewText(R.id.streak_days, days.toString())
                v.setTextViewText(R.id.streak_label, label)
                v.setProgressBar(R.id.streak_progress, 100, progress, false)
                v.setTextViewText(R.id.streak_next, hint)
                MuraWidgets.clickThrough(context, v, R.id.streak_root)
            }
        }
    }
}

/** Daily spiritual insight - calm card; text and source cross-fade. */
class InsightWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        renderAll(context)
    }
    companion object {
        fun renderAll(context: Context) {
            val insight = MuraWidgets.text(context, "insight", "Be still, and know.")
            val source = MuraWidgets.text(context, "insight_source", "")
            MuraWidgets.update(context, InsightWidgetProvider::class.java, R.layout.insight_widget) { v ->
                v.setTextViewText(R.id.insight_text, insight)
                if (source.isNotBlank()) v.setTextViewText(R.id.insight_source, "— $source")
                MuraWidgets.clickThrough(context, v, R.id.insight_root)
            }
        }
    }
}

/** Today's checklist - tall list with a day-progress bar. */
class HabitsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        renderAll(context)
    }
    companion object {
        fun renderAll(context: Context) {
            val names = MuraWidgets.stringList(context, "habits_names")
            val states = MuraWidgets.stringList(context, "habits_states")
            val doneCount = states.count { it == "1" }
            MuraWidgets.update(context, HabitsWidgetProvider::class.java, R.layout.habits_widget) { v ->
                val summary = if (names.isEmpty()) "" else doneCount.toString() + "/" + names.size.toString() + " done"
                v.setTextViewText(R.id.habits_done, summary)
                // Day progress: fills as the checklist clears.
                v.setProgressBar(
                    R.id.habits_progress, 100,
                    if (names.isEmpty()) 0 else (doneCount * 100) / names.size,
                    false,
                )
                if (names.isEmpty()) {
                    v.setViewVisibility(R.id.habits_rows, android.view.View.GONE)
                    v.setViewVisibility(R.id.habits_empty, android.view.View.VISIBLE)
                } else {
                    v.setViewVisibility(R.id.habits_rows, android.view.View.VISIBLE)
                    v.setViewVisibility(R.id.habits_empty, android.view.View.GONE)
                    names.take(6).forEachIndexed { i, name ->
                        val row = RemoteViews(context.packageName, R.layout.habits_row)
                        row.setTextViewText(R.id.habit_name, name)
                        val done = states.getOrElse(i) { "0" } == "1"
                        row.setTextViewText(R.id.habit_state, if (done) "DONE" else "OPEN")
                        val color = if (done) 0xFF8A5A1E.toInt() else 0xFF6E5C49.toInt()
                        row.setInt(R.id.habit_state, "setTextColor", color)
                        v.addView(R.id.habits_rows, row)
                    }
                }
                MuraWidgets.clickThrough(context, v, R.id.habits_root)
            }
        }
    }
}
