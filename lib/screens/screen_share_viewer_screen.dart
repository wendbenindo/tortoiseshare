import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/colors.dart';

class ScreenShareViewerScreen extends StatefulWidget {
  final Stream<Uint8List> frameStream;
  final VoidCallback onClose;
  final Function(double x, double y)? onTap;
  
  const ScreenShareViewerScreen({
    super.key,
    required this.frameStream,
    required this.onClose,
    this.onTap,
  });

  @override
  State<ScreenShareViewerScreen> createState() => _ScreenShareViewerScreenState();
}

class _ScreenShareViewerScreenState extends State<ScreenShareViewerScreen> {
  Uint8List? _currentFrame;
  int _framesReceived = 0;
  DateTime? _lastFrameTime;
  double _fps = 0.0;
  
  // Dimensions de l'image (pour calculer le ratio)
  double _imageAspectRatio = 9/16; // Par défaut portrait
  
  @override
  void initState() {
    super.initState();
    
    // Écouter les frames
    widget.frameStream.listen((frameData) {
      if (mounted) {
        setState(() {
          // Décoder les dimensions tous les 50 frames (optimisation) ou au début
          if (_currentFrame == null || _framesReceived % 50 == 0) {
            _updateImageDimensions(frameData);
          }
          
          _currentFrame = frameData;
          _framesReceived++;
          
          // Calculer les FPS
          final now = DateTime.now();
          if (_lastFrameTime != null) {
            final diff = now.difference(_lastFrameTime!).inMilliseconds;
            if (diff > 0) {
              _fps = 1000 / diff;
            }
          }
          _lastFrameTime = now;
        });
      }
    });
  }
  
  Future<void> _updateImageDimensions(Uint8List bytes) async {
    try {
      final buffer = await ui.instantiateImageCodec(bytes);
      final frameInfo = await buffer.getNextFrame();
      final image = frameInfo.image;
      if (mounted) {
        setState(() {
          _imageAspectRatio = image.width / image.height;
        });
      }
    } catch (e) {
      // Ignorer erreur de décodage
    }
  }

  void _handleTapDown(TapDownDetails details, double screenWidth, double screenHeight) {
    if (widget.onTap == null || _currentFrame == null) return;

    // Calculer les dimensions réelles de l'image affichée (BoxFit.contain)
    double renderWidth, renderHeight;
    double screenRatio = screenWidth / screenHeight;

    if (screenRatio > _imageAspectRatio) {
      // L'écran est plus large que l'image -> Bandes noires sur les côtés
      renderHeight = screenHeight;
      renderWidth = screenHeight * _imageAspectRatio;
    } else {
      // L'écran est plus haut que l'image -> Bandes noires en haut/bas
      renderWidth = screenWidth;
      renderHeight = screenWidth / _imageAspectRatio;
    }

    // Offset de l'image (centrée)
    double offsetX = (screenWidth - renderWidth) / 2;
    double offsetY = (screenHeight - renderHeight) / 2;

    // Coordonnées locales du clic
    double localX = details.localPosition.dx;
    double localY = details.localPosition.dy;

    // Vérifier si le clic est DANS l'image
    if (localX >= offsetX && localX <= offsetX + renderWidth &&
        localY >= offsetY && localY <= offsetY + renderHeight) {
      
      // Convertir en pourcentage (0.0 -> 1.0)
      double percentX = (localX - offsetX) / renderWidth;
      double percentY = (localY - offsetY) / renderHeight;
      
      print('🖱️ Clic à ${percentX.toStringAsFixed(2)}, ${percentY.toStringAsFixed(2)}');
      widget.onTap!(percentX * 720, percentY * 1280); // Provisoire: on envoie coords base
      // Mieux: envoyer pourcentage, et le mobile convertit
      // Pour l'instant on envoie pourcentage dans le code appelant
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Affichage du frame avec détection de clics
            LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) => _handleTapDown(
                    details, 
                    constraints.maxWidth, 
                    constraints.maxHeight
                  ),
                  child: Center(
                    child: _currentFrame != null
                        ? Image.memory(
                            _currentFrame!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              const SizedBox(height: 20),
                              Text(
                                'En attente du partage d\'écran...',
                                style: TextStyle(color: Colors.white, fontSize: 16),
                              ),
                            ],
                          ),
                  ),
                );
              }
            ),
            
            // Header avec infos et bouton fermer
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Infos
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.white, size: 8),
                          const SizedBox(width: 6),
                          Text(
                            'EN DIRECT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // FPS
                    if (_fps > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_fps.toStringAsFixed(1)} FPS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    Spacer(),
                    // Bouton fermer
                    IconButton(
                      onPressed: widget.onClose,
                      icon: Icon(Icons.close, color: Colors.white, size: 28),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Footer avec stats
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.desktop_windows, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Partage d\'écran PC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '•',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '$_framesReceived frames',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
