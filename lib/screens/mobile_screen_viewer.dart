import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/colors.dart';

class MobileScreenViewer extends StatefulWidget {
  final VoidCallback onClose;
  
  const MobileScreenViewer({
    super.key,
    required this.onClose,
  });

  @override
  State<MobileScreenViewer> createState() => MobileScreenViewerState();
}

class MobileScreenViewerState extends State<MobileScreenViewer> {
  Uint8List? _currentFrame;
  int _framesReceived = 0;
  DateTime? _lastFrameTime;
  double _fps = 0.0;
  
  // Méthode publique pour mettre à jour le frame
  void updateFrame(Uint8List frameData) {
    if (mounted) {
      setState(() {
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
            decoration: BoxDecoration(
              color: AppColors.primary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose,
                  icon: Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Fermer',
                ),
                const SizedBox(width: 12),
                Icon(Icons.smartphone, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Écran du mobile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_fps > 0)
                        Text(
                          '${_fps.toStringAsFixed(1)} FPS • $_framesReceived frames',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 12),
                
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
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
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Affichage du frame avec cadre de téléphone
          Expanded(
            child: _currentFrame != null
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
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
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            _currentFrame!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.smartphone,
                            size: 80,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          'En attente du partage d\'écran...',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Démarrez le partage depuis le mobile',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
