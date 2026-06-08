package com.example.eq_master

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.tuapp/audio_hardware"
    
    // Convertimos todos los chips en objetos GLOBALES (Inmortales)
    companion object {
        var equalizer: Equalizer? = null
        var preAmp: LoudnessEnhancer? = null
        var bassBoost: BassBoost? = null
        var virtualizer: Virtualizer? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --- PEDIR PERMISO DE NOTIFICACIÓN EN ANDROID 13+ ---
        if (Build.VERSION.SDK_INT >= 33) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }

        // 1. Arrancamos el Servicio Inmortal en segundo plano
        val serviceIntent = Intent(this, AudioService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        // 2. Inicializamos TODO el hardware de audio en la sesión global (0)
        if (equalizer == null) {
            try { equalizer = Equalizer(100, 0) } catch (e: Exception) { println("Error EQ: ${e.message}") }
        }

        if (preAmp == null) {
            try { preAmp = LoudnessEnhancer(0) } catch (e: Exception) { println("Error Pre-Amp: ${e.message}") }
        }

        if (bassBoost == null) {
            try { bassBoost = BassBoost(0, 0) } catch (e: Exception) { println("Error BassBoost: ${e.message}") }
        }

        if (virtualizer == null) {
            try { virtualizer = Virtualizer(0, 0) } catch (e: Exception) { println("Error Virtualizer: ${e.message}") }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnable" -> {
                    val isEnabled = call.argument<Boolean>("enable") ?: false
                    try {
                        equalizer?.enabled = isEnabled
                        preAmp?.enabled = isEnabled
                        bassBoost?.enabled = isEnabled
                        virtualizer?.enabled = isEnabled
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("HARDWARE_ERROR", "No se pudo cambiar el estado: ${e.message}", null)
                    }
                }

                "setPreAmp" -> {
                    val gain = call.argument<Int>("gain") ?: 0
                    if (preAmp != null) {
                        try {
                            preAmp?.setTargetGain(gain * 100)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("HARDWARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("UNAVAILABLE", "Módulo de ganancia no disponible", null)
                    }
                }

                // --- NUEVO: CONTROL DE BASS BOOST ---
                "setBassBoost" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    if (bassBoost != null && bassBoost?.strengthSupported == true) {
                        try {
                            // La fuerza nativa va de 0 a 1000
                            bassBoost?.setStrength(strength.toShort())
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("HARDWARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("UNAVAILABLE", "BassBoost no soportado por este dispositivo", null)
                    }
                }

                // --- NUEVO: CONTROL DE VIRTUALIZER 3D ---
                "setVirtualizer" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    if (virtualizer != null && virtualizer?.strengthSupported == true) {
                        try {
                            // La fuerza nativa va de 0 a 1000
                            virtualizer?.setStrength(strength.toShort())
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("HARDWARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("UNAVAILABLE", "Virtualizer no soportado por este dispositivo", null)
                    }
                }

                "getBands" -> {
                    if (equalizer != null) {
                        val bands = equalizer?.numberOfBands?.toInt() ?: 0
                        result.success(bands)
                    } else {
                        result.error("UNAVAILABLE", "Ecualizador no encontrado", null)
                    }
                }

                "getCenterFrequencies" -> {
                    if (equalizer != null) {
                        val bands = equalizer?.numberOfBands?.toInt() ?: 0
                        val frequencies = mutableListOf<Int>()
                        for (i in 0 until bands) {
                            frequencies.add(equalizer?.getCenterFreq(i.toShort()) ?: 0)
                        }
                        result.success(frequencies)
                    } else {
                        result.error("UNAVAILABLE", "Ecualizador no encontrado", null)
                    }
                }

                "setBandLevel" -> {
                    val band = call.argument<Int>("band")?.toShort()
                    val level = call.argument<Int>("level") ?: 0
                    val maxBands = equalizer?.numberOfBands?.toInt() ?: 0

                    if (equalizer != null && band != null && band < maxBands) {
                        try {
                            equalizer?.setBandLevel(band, (level * 100).toShort())
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("HARDWARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PARAMS", "Banda inexistente", null)
                    }
                }

                // --- NUEVO: BOTÓN DE APAGADO TOTAL (KILL SWITCH) ---
                "killApp" -> {
                    try {
                        // 1. Apagamos los chips para que la música vuelva a la normalidad
                        equalizer?.enabled = false
                        preAmp?.enabled = false
                        bassBoost?.enabled = false
                        virtualizer?.enabled = false
                        
                        // 2. Matamos el Servicio Inmortal de Android
                        val serviceIntent = Intent(this@MainActivity, AudioService::class.java)
                        stopService(serviceIntent)
                        
                        result.success(true)
                        
                        // 3. Cerramos la aplicación por completo
                        finishAffinity()
                        kotlin.system.exitProcess(0)
                    } catch (e: Exception) {
                        result.error("KILL_ERROR", "Error al cerrar la app: ${e.message}", null)
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }
}