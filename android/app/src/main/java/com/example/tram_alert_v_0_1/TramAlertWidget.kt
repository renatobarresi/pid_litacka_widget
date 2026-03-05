package com.example.tram_alert_v_0_1

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Implementation of App Widget functionality.
 */
class TramAlertWidget : HomeWidgetProvider() {
    companion object {
        private const val STATION_COUNT = 3
        private const val WIDGET_ROWS_PER_STATION = 5
    }

    private fun tramDataKey(stationNumber: Int, tramNumber: Int): String {
        return "station_num_${stationNumber},arriving_tram_data_num_${tramNumber}"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        // There may be multiple widgets active, so update all of them
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.tram_alert_widget).apply {
                // Set station names
                for (station in 1..STATION_COUNT) {
                    val stationName = widgetData.getString("station_name_$station", null)
                    val stationNameId = when (station) {
                        1 -> R.id.station_name_1_id
                        2 -> R.id.station_name_2_id
                        3 -> R.id.station_name_3_id
                        else -> R.id.station_name_1_id
                    }
                    setTextViewText(stationNameId, stationName ?: "Station $station")
                }

                val rowIds = listOf(
                    R.id.tram_no_1_id,
                    R.id.tram_no_2_id,
                    R.id.tram_no_3_id,
                    R.id.tram_no_4_id,
                    R.id.tram_no_5_id,
                    R.id.tram_no_6_id,
                    R.id.tram_no_7_id,
                    R.id.tram_no_8_id,
                    R.id.tram_no_9_id,
                    R.id.tram_no_10_id,
                    R.id.tram_no_11_id,
                    R.id.tram_no_12_id,
                    R.id.tram_no_13_id,
                    R.id.tram_no_14_id,
                    R.id.tram_no_15_id,
                )

                for (rowIndex in rowIds.indices) {
                    val stationNumber = (rowIndex / WIDGET_ROWS_PER_STATION) + 1
                    val tramNumber = (rowIndex % WIDGET_ROWS_PER_STATION) + 1
                    val tramText = widgetData.getString(tramDataKey(stationNumber, tramNumber), null)
                    setTextViewText(
                        rowIds[rowIndex],
                        tramText ?: "No data received from app"
                    )
                }

                // Get time data was fetched
                val timeDataWasFetched = widgetData.getString("last_updated_time", null)
                setTextViewText(R.id.last_updated_time_id, timeDataWasFetched ?: "")

                // Get and display error message if any
                val errorMessage = widgetData.getString("error_message", null)
                setTextViewText(R.id.error_message_id, errorMessage ?: "")

                // Set button click to trigger background callback
                val refreshIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("homeWidgetTramAlert://refresh")
                )
                setOnClickPendingIntent(R.id.button, refreshIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onEnabled(context: Context) {
        // Enter relevant functionality for when the first widget is created
    }

    override fun onDisabled(context: Context) {
        // Enter relevant functionality for when the last widget is disabled
    }
}