import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';

// Service pour gérer l'historique des connexions
class ConnectionHistoryService {
  static const String _historyKey = 'connection_history';
  static const String _lastConnectionKey = 'last_connection';
  static const int _maxHistorySize = 10; // Garder max 10 connexions

  // Sauvegarder une connexion réussie
  static Future<void> saveSuccessfulConnection(Device device) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Sauvegarder comme dernière connexion
    await prefs.setString(_lastConnectionKey, jsonEncode(device.toJson()));
    
    // Ajouter à l'historique
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    
    // Supprimer l'ancienne entrée si elle existe
    history.removeWhere((item) {
      final deviceData = jsonDecode(item);
      return deviceData['ipAddress'] == device.ipAddress;
    });
    
    // Ajouter en première position
    history.insert(0, jsonEncode(device.toJson()));
    
    // Limiter la taille de l'historique
    if (history.length > _maxHistorySize) {
      history = history.take(_maxHistorySize).toList();
    }
    
    await prefs.setStringList(_historyKey, history);
    print('💾 Connexion sauvegardée: ${device.name} (${device.ipAddress})');
  }
  
  // Récupérer la dernière connexion
  static Future<Device?> getLastConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final lastConnectionJson = prefs.getString(_lastConnectionKey);
    
    if (lastConnectionJson != null) {
      try {
        final deviceData = jsonDecode(lastConnectionJson);
        return Device.fromJson(deviceData);
      } catch (e) {
        print('❌ Erreur lecture dernière connexion: $e');
      }
    }
    
    return null;
  }
  
  // Récupérer l'historique complet
  static Future<List<Device>> getConnectionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    
    List<Device> devices = [];
    for (String deviceJson in history) {
      try {
        final deviceData = jsonDecode(deviceJson);
        devices.add(Device.fromJson(deviceData));
      } catch (e) {
        print('❌ Erreur lecture historique: $e');
      }
    }
    
    return devices;
  }
  
  // Supprimer une connexion de l'historique
  static Future<void> removeFromHistory(String ipAddress) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    
    history.removeWhere((item) {
      final deviceData = jsonDecode(item);
      return deviceData['ipAddress'] == ipAddress;
    });
    
    await prefs.setStringList(_historyKey, history);
    
    // Si c'était la dernière connexion, la supprimer aussi
    final lastConnection = await getLastConnection();
    if (lastConnection?.ipAddress == ipAddress) {
      await prefs.remove(_lastConnectionKey);
    }
  }
  
  // Vider tout l'historique
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    await prefs.remove(_lastConnectionKey);
    print('🗑️ Historique des connexions vidé');
  }
  
  // Vérifier si une IP est dans l'historique
  static Future<bool> isInHistory(String ipAddress) async {
    final history = await getConnectionHistory();
    return history.any((device) => device.ipAddress == ipAddress);
  }
  
  // Mettre à jour le nom d'un device dans l'historique
  static Future<void> updateDeviceName(String ipAddress, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    
    for (int i = 0; i < history.length; i++) {
      final deviceData = jsonDecode(history[i]);
      if (deviceData['ipAddress'] == ipAddress) {
        deviceData['name'] = newName;
        history[i] = jsonEncode(deviceData);
        break;
      }
    }
    
    await prefs.setStringList(_historyKey, history);
    
    // Mettre à jour la dernière connexion aussi
    final lastConnection = await getLastConnection();
    if (lastConnection?.ipAddress == ipAddress) {
      final updatedDevice = lastConnection!.copyWith(name: newName);
      await prefs.setString(_lastConnectionKey, jsonEncode(updatedDevice.toJson()));
    }
  }
}