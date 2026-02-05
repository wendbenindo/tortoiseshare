import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

// Service de partage d'écran mobile optimisé
class MobileScreenShareService {
  Timer? _captureTimer;
  bool _isSharing = false;
  bool _isCapturing = false; // Pour éviter les captures simultanées
  GlobalKey? _screenKey;
  DateTime? _lastCaptureTime;
  
  // Callback pour envoyer les frames
  Function(Uint8List)? onFrameCaptured;
  
  // FPS du partage - MAXIMISÉ pour instantanéité
  int fps = 30; // 30 FPS pour réactivité quasi-instantanée!
  
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
  
  // Capturer l'écran du mobile avec qualité optimisée
  Future<void> _captureScreen() async {
    // Éviter les captures simultanées
    if (_isCapturing || _screenKey?.currentContext == null) return;
    
    // Throttling: éviter de capturer trop rapidement
    final now = DateTime.now();
    if (_lastCaptureTime != null) {
      final elapsed = now.difference(_lastCaptureTime!).inMilliseconds;
      if (elapsed < 28) return; // Min 28ms entre captures (max 35 FPS)
    }
    
    _isCapturing = true;
    _lastCaptureTime = now;
    
    try {
      // Obtenir le RenderObject
      final RenderRepaintBoundary boundary = 
          _screenKey!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      // ✅ HAUTE RÉSOLUTION pour qualité nette (0.8 au lieu de 0.3)
      final ui.Image image = await boundary.toImage(pixelRatio: 0.8);
      
      // Convertir en RGBA pour traitement
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      
      if (byteData != null) {
        // Créer image pour compression JPEG
        final imgLib = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: byteData.buffer,
          numChannels: 4,
        );
        
        // ✅ COMPRESSION JPEG haute qualité (quality 90 pour netteté maximale)
        final jpegBytes = Uint8List.fromList(
          img.encodeJpg(imgLib, quality: 90)
        );
        
        // Stats pour debug (première frame seulement)
        if (_framesCounter == 0) {
          print('📸 Partage écran: ${image.width}x${image.height}px → ${jpegBytes.length} bytes JPEG');
        }
        _framesCounter++;
        
        // ✅ Limite augmentée (500KB au lieu de 200KB)
        if (jpegBytes.length < 500000) {
          onFrameCaptured?.call(jpegBytes);
        } else {
          print('⚠️ Frame trop gros: ${jpegBytes.length} bytes, compression additionnelle...');
          // Compression plus agressive si nécessaire
          final smallerJpeg = Uint8List.fromList(
            img.encodeJpg(imgLib, quality: 70)
          );
          if (smallerJpeg.length < 500000) {
            onFrameCaptured?.call(smallerJpeg);
          } else {
            print('❌ Frame toujours trop gros, ignoré');
          }
        }
      }
      
      image.dispose();
    } catch (e) {
      print('❌ Erreur capture mobile: $e');
    } finally {
      _isCapturing = false;
    }
  }
  
  int _framesCounter = 0;
  
  // Nettoyer les ressources
  void dispose() {
    stopSharing();
  }
}
