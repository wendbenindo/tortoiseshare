// État de la connexion
enum ConnectionStatus {
  idle,           // Pas de connexion
  scanning,       // Scan en cours
  connecting,     // Connexion en cours
  connected,      // Connecté
  disconnected,   // Déconnecté
  error,          // Erreur
}

// Classe pour gérer l'état avec un message
class AppConnectionState {
  final ConnectionStatus status;
  final String message;
  final String? errorMessage;

  AppConnectionState({
    required this.status,
    required this.message,
    this.errorMessage,
  });

  AppConnectionState.idle()
      : status = ConnectionStatus.idle,
        message = 'Appuyez sur "Rechercher" pour trouver un PC',
        errorMessage = null;

  AppConnectionState.scanning(String msg)
      : status = ConnectionStatus.scanning,
        message = msg,
        errorMessage = null;

  AppConnectionState.connected(String deviceName)
      : status = ConnectionStatus.connected,
        message = '✅ Connecté à $deviceName',
        errorMessage = null;

  AppConnectionState.error(String error)
      : status = ConnectionStatus.error,
        message = '❌ Erreur',
        errorMessage = error;

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isScanning => status == ConnectionStatus.scanning;
}
