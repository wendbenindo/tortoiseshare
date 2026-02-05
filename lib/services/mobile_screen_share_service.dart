import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// Service de partage d'écran mobile
class MobileScreenShareService {
  Timer? _captureTimer;
  bool _isSharing = false;
  bool _isCapturing = false; // Pour éviter les captures simultanées
  GlobalKey? _screenKey;
  
  // Callback pour envoyer les frames
  Function(Uint8List)? onFrameCaptured;
  
  // FPS du partage (réduit pour meilleures performances)
  int fps = 3; // 3 FPS au lieu de 5 pour réduire la charge
  
  bool get isSharing => _isSharing;
  
  // Démarrer le partage d'écran
  Future<bool> startSharing(GlobalKey screenKey) async {
    if (_isSharing) return false;
    
    try {
      _screenKey = screenKey;
      _isSharing = true;
      
      // Capturer l'écran à intervalles réguliers
      final interval = Duration(milliseconds: (1000 / fps).round());
      _captureTimer = Timer.periodic(interval, (_) => _captureScreen());
      
      print('✅ Partage d\'écran mobile démarré ($fps FPS)');
      return true;
    } catch (e) {
      print('❌ Erreur démarrage partage: $e');
      return false;
    }
  }
  
  // Arrêter le partage d'écran
  void stopSharing() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _isSharing = false;
    _isCapturing = false;
    _screenKey = null;
    print('🛑 Partage d\'écran mobile arrêté');
  }
  
  // Capturer l'écran du mobile
  Future<void> _captureScreen() async {
    // Éviter les captures simultanées
    if (_isCapturing || _screenKey?.currentContext == null) return;
    
    _isCapturing = true;
    
    try {
      // Obtenir le RenderObject
      final RenderRepaintBoundary boundary = 
          _screenKey!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      // Capturer l'image avec résolution très réduite pour performances
      final ui.Image image = await boundary.toImage(pixelRatio: 0.3);
      
      // Convertir directement en PNG
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        
        // Log seulement le premier frame pour debug
        if (_isSharing) {
          print('📸 Frame: ${pngBytes.length} bytes (${image.width}x${image.height}px)');
        }
        
        // Envoyer via callback seulement si pas trop gros
        if (pngBytes.length < 200000) { // Max 200 KB
          onFrameCaptured?.call(pngBytes);
        } else {
          print('⚠️ Frame trop gros: ${pngBytes.length} bytes, ignoré');
        }
      }
      
      image.dispose();
    } catch (e) {
      print('❌ Erreur capture mobile: $e');
    } finally {
      _isCapturing = false;
    }
  }
  
  // Compresser l'image en PNG (méthode non utilisée, gardée pour référence)
  Future<Uint8List> _compressToPng(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
  
  // Nettoyer les ressources
  void dispose() {
    stopSharing();
  }
}
