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
        // Creamos la notificación que hace a la app "Inmortal"
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PURE DSP CONTROL")
            .setContentText("Mejorando el audio en segundo plano")
            .setSmallIcon(android.R.drawable.ic_media_play) // Icono nativo de Android
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true) // Evita que el usuario la borre deslizando
            .build()

        // Le decimos a Android: "Soy un servicio vital, no me mates"
        startForeground(1, notification)

        // START_STICKY hace que si el sistema colapsa y cierra la app, la vuelva a abrir automáticamente
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null // No necesitamos comunicación directa por Binder
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Ecualizador Background Service",
                NotificationManager.IMPORTANCE_LOW // Low para que no haga ruido al aparecer
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Si el usuario fuerza la detención de la app desde los ajustes, ahí sí liberamos el chip
        MainActivity.equalizer?.release()
        MainActivity.equalizer = null
    }
}