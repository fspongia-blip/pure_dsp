package com.example.eq_master

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AudioService : Service() {

    private val CHANNEL_ID = "EQ_Service_Channel"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Si Android intenta recrear el servicio en segundo plano con intent null, lo detenemos
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PURE DSP CONTROL")
            .setContentText("Mejorando el audio en segundo plano")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        // Evita cierres si Android bloquea el primer plano por estado de batería, fondo o permisos
        try {
            startForeground(1, notification)
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }

        // START_NOT_STICKY evita que Android 12+ reinicie el servicio en segundo plano sin permiso
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Ecualizador Background Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        MainActivity.equalizer?.release()
        MainActivity.equalizer = null
    }
}