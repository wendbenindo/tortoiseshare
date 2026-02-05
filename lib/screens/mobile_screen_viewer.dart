import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/colors.dart';

class MobileScreenViewer extends StatefulWidget {
  final VoidCallback onClose;
  final Function(double x, double y)? onTap;
  
  const MobileScreenViewer({
    super.key,
    required this.onClose,
    this.onTap,
  });

  @override
  State<MobileScreenViewer> createState() => MobileScreenViewerState();
}

class MobileScreenViewerState extends State<MobileScreenViewer> {
  Uint8List? _currentFrame;
  int _framesReceived = 0;
  DateTime? _lastFrameTime;
  double _fps = 0.0;
  double _imageAspectRatio = 9/16; // Par défaut portrait

  // Méthode publique pour mettre à jour le frame
  void updateFrame(Uint8List frameData) {
    if (mounted) {
      // Décoder les dimensions tous les 50 frames (optimisation)
      if (_currentFrame == null || _framesReceived % 50 == 0) {
        _updateImageDimensions(frameData);
      }
      
      setState(() {
        _currentFrame = frameData;
        _framesReceived++;
        
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

    double offsetX = (screenWidth - renderWidth) / 2;
    double offsetY = (screenHeight - renderHeight) / 2;
    double localX = details.localPosition.dx;
    double localY = details.localPosition.dy;

    // Vérifier si le clic est DANS l'image
    if (localX >= offsetX && localX <= offsetX + renderWidth &&
        localY >= offsetY && localY <= offsetY + renderHeight) {
      
      // Convertir en pourcentage (0.0 -> 1.0)
      double percentX = (localX - offsetX) / renderWidth;
      double percentY = (localY - offsetY) / renderHeight;
      
      print('🖱️ Clic Control: ${percentX.toStringAsFixed(2)}, ${percentY.toStringAsFixed(2)}');
      widget.onTap!(percentX, percentY);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.primary,
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose,
                  icon: Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Icon(Icons.touch_app, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contrôle à distance',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (_fps > 0)
                        Text('${_fps.toStringAsFixed(1)} FPS • Touchez l\'écran pour cliquer', 
                             style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 8),
                      const SizedBox(width: 6),
                      Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Image interactive
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20), // Espacement autour du téléphone
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapDown: (details) => _handleTapDown(
                      details, 
                      constraints.maxWidth, 
                      constraints.maxHeight
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: Colors.black, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            spreadRadius: 2,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17), // 19 - 2 (border width)
                        child: _currentFrame != null
                            ? Image.memory(
                                _currentFrame!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.high,
                              )
                            : Center(
                                child: CircularProgressIndicator(color: AppColors.primary),
                              ),
                      ),
                    ),
                  );
                }
              ),
            ),
          ),
        ],
      ),
    );
  }
}
