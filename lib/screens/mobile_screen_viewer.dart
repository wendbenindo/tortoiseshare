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
      backgroundColor: Colors.black,
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
          
          // Affichage du frame
          Expanded(
            child: Center(
              child: _currentFrame != null
                  ? Container(
                      constraints: BoxConstraints(
                        maxWidth: 400,
                        maxHeight: 800,
                      ),
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Image.memory(
                        _currentFrame!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 20),
                        Text(
                          'En attente du partage d\'écran...',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Démarrez le partage depuis le mobile',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
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
