import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Service de partage d'écran mobile via MediaProjection Natif
class MobileScreenShareService {
  static const MethodChannel _channel = MethodChannel('com.tortoiseshare/screen_share');
  static const EventChannel _eventChannel = EventChannel('com.tortoiseshare/screen_stream');
  
  StreamSubscription? _streamSubscription;
  bool _isSharing = false;
  
  // Callback pour envoyer les frames
  Function(Uint8List)? onFrameCaptured;
  
  bool get isSharing => _isSharing;
  
  // Démarrer le partage d'écran (Natif Android)
  Future<bool> startSharing(GlobalKey? screenKey) async {
    if (_isSharing) return false;
    
    // Si ce n'est pas Android, on ne peut pas utiliser cette méthode native pour l'instant
    if (!Platform.isAndroid) {
      print('⚠️ Partage d\'écran système supporté uniquement sur Android pour le moment');
      return false;
    }
    
    try {
      print('🚀 Démarrage du partage d\'écran système...');
      
      // 1. Démarrer l'écoute du flux AVANT de lancer la projection
      _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Uint8List) {
            onFrameCaptured?.call(event);
          }
        },
        onError: (error) {
          print('❌ Erreur flux vidéo: $error');
        }
      );
      
      // 2. Demander la permission et lancer le service via canal natif
      final bool started = await _channel.invokeMethod('startScreenShare');
      
      if (started) {
        _isSharing = true;
        print('✅ Partage d\'écran système actif ! (Tout est visible)');
        return true;
      } else {
        print('❌ Échec du démarrage natif');
        await _stopNative();
        return false;
      }
      
    } catch (e) {
      print('❌ Erreur fatal démarrage partage: $e');
      await _stopNative();
      return false;
    }
  }
  
  // Effectuer un clic via AccessibilityService
  Future<void> performClick(double x, double y) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('performClick', {'x': x, 'y': y});
    }
  }

  // Ouvrir les paramètres d'accessibilité
  Future<void> openAccessibilitySettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('openAccessibilitySettings');
    }
  }
  
  // Arrêter le partage d'écran
  Future<void> stopSharing() async {
    await _stopNative();
    print('🛑 Partage d\'écran arrêté');
  }
  
  Future<void> _stopNative() async {
    try {
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      
      if (Platform.isAndroid) {
        await _channel.invokeMethod('stopScreenShare');
      }
    } catch (e) {
      print('⚠️ Erreur arrêt: $e');
    } finally {
      _isSharing = false;
    }
  }
  
  // Nettoyer les ressources
  void dispose() {
    stopSharing();
  }
}
