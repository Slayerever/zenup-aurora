import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AuroraApp());
}

enum OrbState { idle, listening, thinking, speaking }

class AuroraApp extends StatelessWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZEN UP AURORA',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050811),
      ),
      home: const AuroraHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuroraHome extends StatefulWidget {
  const AuroraHome({super.key});

  @override
  State<AuroraHome> createState() => _AuroraHomeState();
}

class _AuroraHomeState extends State<AuroraHome> with TickerProviderStateMixin {
  OrbState _orbState = OrbState.idle;
  String _transcript = "";
  String _auroraResponse = "Toca el orbe para hablar con Aurora";
  String _userName = "Estudiante";
  
  late stt.SpeechToText _speech;
  late AudioPlayer _audioPlayer;
  bool _speechAvailable = false;

  late AnimationController _orbAnimController;
  late AnimationController _bgAnimController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _audioPlayer = AudioPlayer();
    _cargarNombreGuardado();
    _initSpeech();
    _configurarAudioPlayer();
    
    _orbAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _orbAnimController, curve: Curves.easeInOut),
    );

    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
  }

  Future<void> _cargarNombreGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? "Estudiante";
      });
    }
  }

  Future<void> _guardarNombreLocal(String nuevoNombre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', nuevoNombre);
    if (mounted) {
      setState(() {
        _userName = nuevoNombre;
      });
    }
  }

  void _configurarAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        if (state == PlayerState.playing) {
          setState(() => _orbState = OrbState.speaking);
        } else if (state == PlayerState.completed || state == PlayerState.stopped) {
          setState(() => _orbState = OrbState.idle);
        }
      }
    });
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (val) => debugPrint('Error STT: $val'),
      onStatus: (val) {
        if (val == 'done' && _orbState == OrbState.listening) {
          _procesarVozCapturada();
        }
      },
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _orbAnimController.dispose();
    _bgAnimController.dispose();
    _audioPlayer.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleEscucha() async {
    if (_orbState == OrbState.thinking || _orbState == OrbState.speaking) return;

    if (_orbState == OrbState.listening) {
      await _speech.stop();
      _procesarVozCapturada();
    } else {
      if (_speechAvailable) {
        setState(() {
          _orbState = OrbState.listening;
          _transcript = "";
          _auroraResponse = "Te escucho...";
        });

        await _speech.listen(
          onResult: (val) {
            setState(() {
              _transcript = val.recognizedWords;
            });
          },
        );
      } else {
        await _initSpeech();
      }
    }
  }

  Future<void> _procesarVozCapturada() async {
    final mensajeEnviar = _transcript.trim().isNotEmpty 
        ? _transcript 
        : "Hola Aurora, ¿cómo estás?";

    setState(() {
      _orbState = OrbState.thinking;
      _auroraResponse = "Procesando en Oracle Cloud...";
    });

    try {
      final url = Uri.parse('http://150.136.245.134:8000/chat');
      final response = await http.post(
        url,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'texto': mensajeEnviar,
          'nombre': _userName
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final respuestaTexto = data['aurora_dice'] ?? "Sin respuesta";
        final audioB64 = data['audio_b64'] ?? "";

        setState(() {
          _auroraResponse = respuestaTexto;
        });

        if (audioB64.isNotEmpty) {
          Uint8List bytes = base64Decode(audioB64);
          await _audioPlayer.play(BytesSource(bytes));
        } else {
          setState(() => _orbState = OrbState.idle);
        }
      } else {
        setState(() {
          _auroraResponse = "Servidor no disponible momentáneamente (${response.statusCode})";
          _orbState = OrbState.idle;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auroraResponse = "Error de conexión con Oracle Cloud";
        _orbState = OrbState.idle;
      });
    }
  }

  void _mostrarModalAyuda() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.health_and_safety, color: Colors.cyanAccent),
                  SizedBox(width: 10),
                  Text(
                    'Servicios de Bienestar (ZenUp DAE)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _buildHelpTile(Icons.psychology, 'Soporte Psicosocial', 'Acompañamiento en momentos de estrés o ansiedad.'),
              _buildHelpTile(Icons.school, 'Becas y Subsidios DAE', 'Información sobre apoyos socioeconómicos UNIMINUTO.'),
              _buildHelpTile(Icons.sports_soccer, 'Deportes y Cultura', 'Talleres artísticos, torneos y acondicionamiento.'),
              _buildHelpTile(Icons.contact_support, 'Orientación Académica', 'Tutorías para proyectos y materias complejas.'),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHelpTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueAccent),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      onTap: () {
        Navigator.pop(context);
        _transcript = "Cuéntame sobre $title";
        _procesarVozCapturada();
      },
    );
  }

  void _mostrarModalRegistro() {
    final TextEditingController nameController = TextEditingController(text: _userName == "Estudiante" ? "" : _userName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Perfil del Estudiante', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa tu nombre para que Aurora te recuerde siempre en la app:', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 15),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ej: Carlos / Sofía',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            onPressed: () async {
              final textoIngresado = nameController.text.trim();
              if (textoIngresado.isNotEmpty) {
                await _guardarNombreLocal(textoIngresado);
                if (!mounted) return;
                setState(() {
                  _transcript = "Hola Aurora, soy $_userName";
                });
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                _procesarVozCapturada();
              }
            },
            child: const Text('Guardar Nombre', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _llamarSos() async {
    final Uri url = Uri.parse('tel:106');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  List<Color> _obtenerColoresOrbe() {
    switch (_orbState) {
      case OrbState.listening:
        return [Colors.orangeAccent, Colors.deepOrange];
      case OrbState.thinking:
        return [Colors.purpleAccent, Colors.indigo];
      case OrbState.speaking:
        return [Colors.greenAccent, Colors.teal];
      case OrbState.idle:
        return [Colors.cyanAccent, Colors.blueAccent];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = _obtenerColoresOrbe();

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgAnimController,
            builder: (context, child) {
              return CustomPaint(
                painter: StarfieldPainter(
                  progress: _bgAnimController.value,
                  baseColor: colores.first,
                ),
                child: Container(),
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _mostrarModalRegistro,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _userName != "Estudiante" ? Colors.cyanAccent : Colors.white24,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person,
                                size: 14,
                                color: _userName != "Estudiante" ? Colors.cyanAccent : Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _userName != "Estudiante" ? _userName : "Nombre",
                                style: TextStyle(
                                  color: _userName != "Estudiante" ? Colors.cyanAccent : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Text(
                        'ZEN UP AURORA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                      GestureDetector(
                        onTap: _mostrarModalAyuda,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.help_outline, size: 14, color: Colors.cyanAccent),
                              SizedBox(width: 4),
                              Text(
                                'DAE',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _toggleEscucha,
                  child: AnimatedBuilder(
                    animation: _orbAnimController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _orbState == OrbState.listening || _orbState == OrbState.speaking
                            ? _scaleAnimation.value * 1.10
                            : _scaleAnimation.value,
                        child: Container(
                          width: 210,
                          height: 210,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                colores.first.withValues(alpha: 0.95),
                                colores.last.withValues(alpha: 0.5),
                                Colors.transparent,
                              ],
                              stops: const [0.25, 0.65, 1.0],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colores.first.withValues(alpha: 0.35),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              _orbState == OrbState.listening
                                  ? Icons.mic
                                  : (_orbState == OrbState.thinking
                                      ? Icons.auto_awesome
                                      : (_orbState == OrbState.speaking ? Icons.graphic_eq : Icons.circle_outlined)),
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Spacer(),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_transcript.isNotEmpty && _orbState == OrbState.listening)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                '"$_transcript"',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.orangeAccent, 
                                  fontSize: 14, 
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          Text(
                            _auroraResponse,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  icon: const Icon(Icons.warning_amber_rounded, size: 20),
                  label: const Text(
                    'SOS - LÍNEA 106',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  onPressed: _llamarSos,
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StarfieldPainter extends CustomPainter {
  final double progress;
  final Color baseColor;

  StarfieldPainter({required this.progress, required this.baseColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    final paint = Paint();

    for (int i = 0; i < 70; i++) {
      final x = rand.nextDouble() * size.width;
      final yOffset = rand.nextDouble() * size.height;
      
      final loops = (i % 3) + 1;
      final y = (yOffset + progress * size.height * loops) % size.height;
      
      final radius = rand.nextDouble() * 2.0 + 0.5;
      final alpha = (math.sin(progress * math.pi * 2 + i) + 1) / 2 * 0.6 + 0.1;

      paint.color = i % 3 == 0 ? baseColor.withValues(alpha: alpha) : Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) => true;
}