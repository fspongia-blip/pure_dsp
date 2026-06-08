import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

void main() => runApp(const EqualizerApp());

class EqualizerApp extends StatelessWidget {
  const EqualizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.cyanAccent,
        sliderTheme: const SliderThemeData(trackHeight: 4.0),
      ),
      home: const EqualizerScreen(),
    );
  }
}

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  static const platform = MethodChannel('com.tuapp/audio_hardware');

  List<double> bandValues = [];
  List<String> bandFrequencies = [];
  int realBandCount = 0;
  bool isLoaded = false;
  bool isEqEnabled = true;
  String currentPreset = "CUSTOM";

  double preAmpValue = 0.0;
  double bassBoostValue = 0.0;
  double virtualizerValue = 0.0;

  // --- VARIABLES DE COMPRA PRO ---
  bool isProUser = false;
  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  final String _productId = 'pro_version_unlock';

  final Map<String, List<double>> defaultPresets = {
    "FLAT": [0.0, 0.0, 0.0, 0.0, 0.0],
    "BASS": [10.0, 6.0, 0.0, 0.0, 0.0],
    "ROCK": [5.0, 3.0, -2.0, 4.0, 6.0],
    "POP": [-2.0, 2.0, 5.0, 3.0, -2.0],
    "VOCAL": [-3.0, 2.0, 6.0, 4.0, -2.0],
  };

  @override
  void initState() {
    super.initState();
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(
      (purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      },
      onDone: () {
        _subscription.cancel();
      },
      onError: (error) {
        debugPrint("Error en el stream de compras: $error");
      },
    );

    _initApp();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  // --- LÓGICA DE GOOGLE PLAY ---
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        _unlockPro();
        if (purchaseDetails.pendingCompletePurchase) {
          _iap.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // GUARDAVIDAS: Verificamos que la pantalla siga montada
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Error al procesar la compra o cancelada."),
            ),
          );
        }
      }
    }
  }

  Future<void> _unlockPro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_pro_user', true);
    setState(() {
      isProUser = true;
    });
    // GUARDAVIDAS 2: Ya lo teníamos, pero lo mantenemos
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "¡GRACIAS! Ahora eres usuario PRO. Funciones desbloqueadas.",
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _buyPro() async {
    final bool available = await _iap.isAvailable();

    // GUARDAVIDAS 3: Soluciona el primer error de async gap
    if (!mounted) return;

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tienda no disponible en este momento.")),
      );
      return;
    }

    final ProductDetailsResponse response = await _iap.queryProductDetails({
      _productId,
    });

    // GUARDAVIDAS 4: Soluciona el segundo error de async gap
    if (!mounted) return;

    if (response.notFoundIDs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "El producto PRO aún no está configurado en Google Play.",
          ),
        ),
      );
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: productDetails,
    );

    _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  // --- INICIO DE APP NORMAL ---
  String _formatFrequency(int mHz) {
    double hz = mHz / 1000.0;
    if (hz >= 1000) {
      double kHz = hz / 1000.0;
      if (kHz == kHz.toInt().toDouble()) return "${kHz.toInt()}kHz";
      return "${kHz.toStringAsFixed(1)}kHz";
    }
    return "${hz.toInt()}Hz";
  }

  Future<void> _initApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      bool savedEnable = prefs.getBool('eq_enabled') ?? true;
      String savedPreset = prefs.getString('current_preset') ?? "CUSTOM";
      double savedPreAmp = prefs.getDouble('pre_amp') ?? 0.0;
      double savedBass = prefs.getDouble('bass_boost') ?? 0.0;
      double savedVirtualizer = prefs.getDouble('virtualizer') ?? 0.0;

      bool savedIsPro = prefs.getBool('is_pro_user') ?? false;

      await platform.invokeMethod('setEnable', {"enable": true});

      final int bands = await platform.invokeMethod('getBands');

      List<String> loadedFreqs = [];
      try {
        final List<dynamic> rawFreqs = await platform.invokeMethod(
          'getCenterFrequencies',
        );
        for (var mHz in rawFreqs) {
          loadedFreqs.add(_formatFrequency(mHz as int));
        }
      } catch (e) {
        for (int i = 0; i < bands; i++) {
          loadedFreqs.add("B${i + 1}");
        }
      }

      List<double> savedValues = [];
      for (int i = 0; i < bands; i++) {
        savedValues.add(prefs.getDouble('band_$i') ?? 0.0);
        if (savedEnable) _sendToHardware(i, savedValues[i]);
      }

      if (savedEnable) {
        _sendPreAmpToHardware(savedPreAmp);
        if (savedIsPro) {
          _sendBassBoostToHardware(savedBass);
          _sendVirtualizerToHardware(savedVirtualizer);
        }
      }

      setState(() {
        isEqEnabled = savedEnable;
        currentPreset = savedPreset;
        preAmpValue = savedPreAmp;
        bassBoostValue = savedIsPro ? savedBass : 0.0;
        virtualizerValue = savedIsPro ? savedVirtualizer : 0.0;
        realBandCount = bands;
        bandValues = savedValues;
        bandFrequencies = loadedFreqs;
        isProUser = savedIsPro;
        isLoaded = true;
      });
    } on PlatformException catch (e) {
      debugPrint("Error de inicio: ${e.message}");
    }
  }

  Future<void> _toggleEQ(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('eq_enabled', value);
    setState(() => isEqEnabled = value);

    if (value) {
      _sendPreAmpToHardware(preAmpValue);
      if (isProUser) {
        _sendBassBoostToHardware(bassBoostValue);
        _sendVirtualizerToHardware(virtualizerValue);
      }
    } else {
      _sendPreAmpToHardware(0.0);
      _sendBassBoostToHardware(0.0);
      _sendVirtualizerToHardware(0.0);
    }

    for (int i = 0; i < realBandCount; i++) {
      _sendToHardware(i, value ? bandValues[i] : 0.0);
    }
  }

  Future<void> _applyPreset(String presetName) async {
    if (!isEqEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final values = defaultPresets[presetName];

    if (values != null) {
      for (int i = 0; i < realBandCount; i++) {
        double val = i < values.length ? values[i] : 0.0;
        setState(() => bandValues[i] = val);
        await prefs.setDouble('band_$i', val);
        _sendToHardware(i, val);
      }
      setState(() => currentPreset = presetName);
      await prefs.setString('current_preset', presetName);
    }
  }

  Future<void> _updateValueAndHardware(int bandIndex, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('band_$bandIndex', value);
    if (isEqEnabled) _sendToHardware(bandIndex, value);
  }

  Future<void> _sendToHardware(int bandIndex, double value) async {
    try {
      await platform.invokeMethod('setBandLevel', {
        "band": bandIndex,
        "level": value.toInt(),
      });
    } catch (e) {
      debugPrint("Error DSP: $e");
    }
  }

  Future<void> _updatePreAmp(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pre_amp', value);
    if (isEqEnabled) _sendPreAmpToHardware(value);
  }

  Future<void> _sendPreAmpToHardware(double value) async {
    try {
      await platform.invokeMethod('setPreAmp', {"gain": value.toInt()});
    } catch (e) {
      debugPrint("Error Pre-Amp: $e");
    }
  }

  Future<void> _updateBassBoost(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bass_boost', value);
    if (isEqEnabled) _sendBassBoostToHardware(value);
  }

  Future<void> _sendBassBoostToHardware(double value) async {
    try {
      await platform.invokeMethod('setBassBoost', {
        "strength": (value * 10).toInt(),
      });
    } catch (e) {
      debugPrint("Error BassBoost: $e");
    }
  }

  Future<void> _updateVirtualizer(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('virtualizer', value);
    if (isEqEnabled) _sendVirtualizerToHardware(value);
  }

  Future<void> _sendVirtualizerToHardware(double value) async {
    try {
      await platform.invokeMethod('setVirtualizer', {
        "strength": (value * 10).toInt(),
      });
    } catch (e) {
      debugPrint("Error Virtualizer: $e");
    }
  }

  void _resetEQ() async {
    for (int i = 0; i < realBandCount; i++) {
      setState(() => bandValues[i] = 0.0);
      _updateValueAndHardware(i, 0.0);
    }
    setState(() {
      preAmpValue = 0.0;
      bassBoostValue = 0.0;
      virtualizerValue = 0.0;
      currentPreset = "FLAT";
    });
    _updatePreAmp(0.0);
    _updateBassBoost(0.0);
    _updateVirtualizer(0.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_preset', "FLAT");
  }

  // --- NUEVO: Función para matar la app por completo ---
  Future<void> _killApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('eq_enabled', false);
      await platform.invokeMethod('killApp');
    } catch (e) {
      debugPrint("Error cerrando la app: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'PURE DSP CONTROL',
          style: TextStyle(letterSpacing: 2),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!isProUser)
            IconButton(
              icon: const Icon(Icons.restore, color: Colors.white54),
              tooltip: "Restaurar Compra",
              onPressed: () => _iap.restorePurchases(),
            ),
        ],
      ),
      // --- NUEVO MENU LATERAL OCULTO ---
      drawer: Drawer(
        backgroundColor: Colors.grey.shade900,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.black),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.graphic_eq, size: 50, color: Colors.cyanAccent),
                  SizedBox(height: 10),
                  Text(
                    "PURE DSP",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.power_settings_new,
                color: Colors.redAccent,
              ),
              title: const Text(
                "Apagar DSP y Cerrar",
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                "Detiene el proceso en segundo plano",
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
              onTap: _killApp,
            ),
          ],
        ),
      ),
      // --- FIN MENU LATERAL ---
      body: !isLoaded
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : Column(
              children: [
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "OFF",
                      style: TextStyle(
                        color: isEqEnabled ? Colors.grey : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Switch(
                      value: isEqEnabled,
                      onChanged: _toggleEQ,
                      activeTrackColor: Colors.cyanAccent.withValues(
                        alpha: 0.5,
                      ),
                      activeThumbColor: Colors.cyanAccent,
                      inactiveThumbColor: Colors.grey,
                      inactiveTrackColor: Colors.grey.shade900,
                    ),
                    Text(
                      "ON",
                      style: TextStyle(
                        color: isEqEnabled ? Colors.greenAccent : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  isEqEnabled ? "HARDWARE ACTIVE" : "BYPASS MODE",
                  style: TextStyle(
                    color: isEqEnabled ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 15),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _buildPresetChip("FLAT"),
                      _buildPresetChip("BASS"),
                      _buildPresetChip("ROCK"),
                      _buildPresetChip("POP"),
                      _buildPresetChip("VOCAL"),
                      _buildPresetChip("CUSTOM"),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(
                    top: 15.0,
                    left: 20.0,
                    right: 20.0,
                  ),
                  child: Column(
                    children: [
                      Text(
                        "PRE-AMP / GAIN: ${preAmpValue.toInt()}dB",
                        style: TextStyle(
                          color: isEqEnabled
                              ? Colors.orangeAccent
                              : Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(
                          context,
                        ).copyWith(trackHeight: 4.0),
                        child: Slider(
                          value: preAmpValue,
                          min: -15.0,
                          max: 15.0,
                          activeColor: isEqEnabled
                              ? Colors.orangeAccent
                              : Colors.grey.shade800,
                          inactiveColor: isEqEnabled
                              ? Colors.orangeAccent.withValues(alpha: 0.2)
                              : Colors.grey.shade900,
                          onChanged: isEqEnabled
                              ? (newValue) {
                                  setState(() => preAmpValue = newValue);
                                  _updatePreAmp(newValue);
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        realBandCount,
                        (index) => _buildVerticalSlider(index),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildEffectSlider(
                          "BASS BOOST",
                          bassBoostValue,
                          Colors.deepPurpleAccent,
                          (val) {
                            setState(() => bassBoostValue = val);
                            _updateBassBoost(val);
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildEffectSlider(
                          "3D SURROUND",
                          virtualizerValue,
                          Colors.tealAccent,
                          (val) {
                            setState(() => virtualizerValue = val);
                            _updateVirtualizer(val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(bottom: 15, top: 10),
                  child: OutlinedButton(
                    onPressed: isEqEnabled ? _resetEQ : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isEqEnabled
                            ? Colors.white
                            : Colors.grey.shade800,
                      ),
                    ),
                    child: Text(
                      "RESET ALL",
                      style: TextStyle(
                        color: isEqEnabled
                            ? Colors.white
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEffectSlider(
    String label,
    double value,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return GestureDetector(
      onTap: () {
        if (!isProUser) _buyPro();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: isProUser ? 1.0 : 0.3,
            child: Column(
              children: [
                Text(
                  "$label: ${value.toInt()}%",
                  style: TextStyle(
                    color: isEqEnabled ? color : Colors.grey.shade700,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 3.0),
                  child: Slider(
                    value: value,
                    min: 0.0,
                    max: 100.0,
                    activeColor: isEqEnabled ? color : Colors.grey.shade800,
                    inactiveColor: isEqEnabled
                        ? color.withValues(alpha: 0.2)
                        : Colors.grey.shade900,
                    onChanged: (isEqEnabled && isProUser) ? onChanged : null,
                  ),
                ),
              ],
            ),
          ),

          if (!isProUser)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent, width: 2),
              ),
              child: const Icon(Icons.lock, color: Colors.redAccent, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String name) {
    bool isSelected = currentPreset == name;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(
          name,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        selected: isSelected,
        selectedColor: Colors.cyanAccent,
        backgroundColor: Colors.grey.shade900,
        side: BorderSide(
          color: isSelected ? Colors.cyanAccent : Colors.grey.shade800,
        ),
        onSelected: (bool selected) {
          if (name != "CUSTOM" && isEqEnabled) _applyPreset(name);
        },
      ),
    );
  }

  Widget _buildVerticalSlider(int index) {
    return Column(
      children: [
        Text(
          "${bandValues[index].toInt()}dB",
          style: TextStyle(
            fontSize: 12,
            color: isEqEnabled ? Colors.white : Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: bandValues[index],
              min: -15.0,
              max: 15.0,
              activeColor: isEqEnabled
                  ? Colors.cyanAccent
                  : Colors.grey.shade800,
              inactiveColor: isEqEnabled
                  ? Colors.cyanAccent.withValues(alpha: 0.2)
                  : Colors.grey.shade900,
              onChanged: isEqEnabled
                  ? (newValue) async {
                      setState(() {
                        bandValues[index] = newValue;
                        currentPreset = "CUSTOM";
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('current_preset', "CUSTOM");
                      _updateValueAndHardware(index, newValue);
                    }
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(
              color: isEqEnabled ? Colors.cyanAccent : Colors.grey.shade800,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            bandFrequencies.isNotEmpty
                ? bandFrequencies[index]
                : "B${index + 1}",
            style: TextStyle(
              color: isEqEnabled ? Colors.cyanAccent : Colors.grey.shade700,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
