import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

class DesktopApp extends StatefulWidget {
  const DesktopApp({super.key});

  @override
  State<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends State<DesktopApp> {
  ServerSocket? _server;
  List<Socket> _clients = [];
  String _status = 'Prêt à communiquer';
  List<Map<String, dynamic>> _logs = [];
  bool _isServerRunning = false;
  String? _serverIP;
  int _connectedDevices = 0;
  int _messagesReceived = 0;

  // Couleurs du thème TortoiseShare
  final Color _primaryColor = const Color(0xFF4CAF50);
  final Color _secondaryColor = const Color(0xFF8BC34A);
  final Color _accentColor = const Color(0xFF795548);
  final Color _backgroundColor = const Color(0xFFF5F5F5);
  final Color _cardColor = Colors.white;
  final Color _textColor = const Color(0xFF333333);

  @override
  void initState() {
    super.initState();
    _getLocalIP();
  }

  Future<void> _getLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.address.startsWith('127.')) {
            setState(() {
              _serverIP = addr.address;
            });
            return;
          }
        }
      }
    } catch (e) {
      print('Erreur IP: $e');
    }
  }

  Future<void> _toggleServer() async {
    if (_isServerRunning) {
      _stopServer();
    } else {
      await _startServer();
    }
  }

  Future<void> _startServer() async {
    try {
      _server = await ServerSocket.bind('0.0.0.0', 8081);
      
      setState(() {
        _isServerRunning = true;
        _status = '✅ Communication autorisée';
        _addLog('Serveur démarré sur le port 8081', 'system', Icons.check_circle);
      });

      _server!.listen((Socket client) {
        _handleNewClient(client);
      });
      
    } catch (e) {
      setState(() {
        _status = '❌ Erreur: $e';
        _addLog('Erreur: $e', 'error', Icons.error);
      });
    }
  }

  void _stopServer() {
    for (final client in _clients) {
      client.destroy();
    }
    _server?.close();
    
    setState(() {
      _isServerRunning = false;
      _clients.clear();
      _status = 'Communication désactivée';
      _connectedDevices = 0;
      _addLog('Serveur arrêté', 'system', Icons.stop_circle);
    });
  }

  void _handleNewClient(Socket client) {
    final ip = client.remoteAddress.address;
    final port = client.remotePort;
    
    setState(() {
      _clients.add(client);
      _connectedDevices = _clients.length;
      _addLog('Appareil connecté: $ip', 'connect', Icons.device_hub);
    });

    client.write('SERVER|NAME|PC-${_serverIP?.split('.').last ?? 'TortoiseShare'}\n');

    client.listen((List<int> data) {
      final message = utf8.decode(data).trim();
      _handleClientMessage(message, ip);
    },
    onDone: () {
      setState(() {
        _clients.remove(client);
        _connectedDevices = _clients.length;
        _addLog('Appareil déconnecté: $ip', 'disconnect', Icons.link_off);
      });
      client.destroy();
    });
  }

  void _handleClientMessage(String message, String clientIP) {
    setState(() {
      _messagesReceived++;
    });
    
    if (message.startsWith('TEXT|')) {
      final text = message.substring(5);
      _addLog(text, 'message', Icons.message, sender: clientIP);
      
      for (final client in _clients) {
        if (client.remoteAddress.address == clientIP) {
          client.write('SERVER|RECEIVED|$text\n');
          break;
        }
      }
      
    } else if (message == 'SCREEN|REQUEST') {
      _addLog('Demande de partage d\'écran', 'screen', Icons.screen_share, sender: clientIP);
      
    } else if (message.startsWith('MOBILE|')) {
      if (message.contains('GET_NAME')) {
        for (final client in _clients) {
          if (client.remoteAddress.address == clientIP) {
            client.write('SERVER|NAME|PC-TortoiseShare\n');
            break;
          }
        }
      }
      _addLog('Connexion mobile établie', 'mobile', Icons.smartphone, sender: clientIP);
    }
  }

  void _addLog(String message, String type, IconData icon, {String? sender}) {
    final log = {
      'message': message,
      'type': type,
      'icon': icon,
      'sender': sender,
      'time': DateTime.now(),
      'color': _getLogColor(type),
    };
    
    setState(() {
      _logs.insert(0, log);
      if (_logs.length > 50) {
        _logs = _logs.sublist(0, 50);
      }
    });
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'system': return Colors.blue;
      case 'connect': return Colors.green;
      case 'disconnect': return Colors.orange;
      case 'message': return _primaryColor;
      case 'screen': return Colors.purple;
      case 'mobile': return Colors.cyan;
      case 'error': return Colors.red;
      default: return _textColor.withOpacity(0.7);
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  void _sendTestMessage() {
    if (_clients.isNotEmpty) {
      _clients.first.write('SERVER|TEST|Message de test du serveur\n');
      _addLog('Message test envoyé', 'system', Icons.send);
    }
  }

  @override
  void dispose() {
    _stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.sensors, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text(
              'TortoiseShare Desktop',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: _primaryColor,
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [
          if (_logs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep, color: Colors.white),
              onPressed: _clearLogs,
              tooltip: 'Effacer les logs',
            ),
          if (_isServerRunning && _clients.isNotEmpty)
            IconButton(
              icon: Icon(Icons.send, color: Colors.white),
              onPressed: _sendTestMessage,
              tooltip: 'Envoyer un message test',
            ),
        ],
      ),
      body: Row(
        children: [
          // Panneau latéral - CORRIGÉ avec SingleChildScrollView
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SingleChildScrollView( // AJOUTÉ pour permettre le défilement
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // En-tête
                    Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _primaryColor.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.desktop_windows,
                            size: 40,
                            color: _primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'TortoiseShare',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _textColor,
                          ),
                        ),
                        Text(
                          'Desktop',
                          style: TextStyle(
                            fontSize: 16,
                            color: _textColor.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // État du serveur
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: _isServerRunning 
                              ? Colors.green.withOpacity(0.3)
                              : Colors.grey.withOpacity(0.2),
                        ),
                      ),
                      color: _isServerRunning 
                          ? Colors.green.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _isServerRunning ? Colors.green : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _status,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: _isServerRunning ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _toggleServer,
                                icon: Icon(
                                  _isServerRunning ? Icons.stop : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  _isServerRunning ? 'DÉSACTIVER' : 'AUTORISER LA COMMUNICATION',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isServerRunning ? Colors.red : _primaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Informations réseau
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Colors.blue.withOpacity(0.2),
                        ),
                      ),
                      color: Colors.blue.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info, color: Colors.blue, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'INFORMATIONS RÉSEAU',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_serverIP != null) ...[
                              _buildInfoRow('Adresse IP', _serverIP!, Icons.network_check),
                              const SizedBox(height: 8),
                            ],
                            _buildInfoRow('Port', '8081', Icons.adjust),
                            const SizedBox(height: 8),
                            _buildInfoRow('Appareils connectés', _connectedDevices.toString(), Icons.device_hub),
                            const SizedBox(height: 8),
                            _buildInfoRow('Messages reçus', _messagesReceived.toString(), Icons.message),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Instructions
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: _accentColor.withOpacity(0.2),
                        ),
                      ),
                      color: _accentColor.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.help, color: _accentColor, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'INSTRUCTIONS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _accentColor,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '1. Cliquez sur "Autoriser la communication"\n'
                              '2. Ouvrez l\'app mobile sur le même réseau WiFi\n'
                              '3. L\'app mobile détectera automatiquement ce PC\n'
                              '4. Les connexions apparaîtront ici',
                              style: TextStyle(
                                fontSize: 13,
                                color: _textColor.withOpacity(0.6),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Version
                    Text(
                      'Version 1.0.0 • TortoiseShare',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: _textColor.withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(height: 8), // Espace supplémentaire en bas
                  ],
                ),
              ),
            ),
          ),
          
          // Panneau principal (logs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ACTIVITÉ EN TEMPS RÉEL',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textColor.withOpacity(0.6),
                          letterSpacing: 1,
                        ),
                      ),
                      if (_logs.isNotEmpty)
                        Text(
                          '${_logs.length} événements',
                          style: TextStyle(
                            fontSize: 12,
                            color: _textColor.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Expanded(
                    child: _logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 80,
                                  color: _textColor.withOpacity(0.2),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Aucune activité',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: _textColor.withOpacity(0.4),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Les connexions et messages\napparaîtront ici',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _textColor.withOpacity(0.3),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            reverse: true,
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              final log = _logs[index];
                              return _buildLogItem(log);
                            },
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

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _textColor.withOpacity(0.5)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: _textColor.withOpacity(0.6),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: log['color'].withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                log['icon'],
                size: 20,
                color: log['color'],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          log['message'],
                          style: TextStyle(
                            fontSize: 14,
                            color: _textColor,
                          ),
                        ),
                      ),
                      Text(
                        _formatTime(log['time'] as DateTime),
                        style: TextStyle(
                          fontSize: 11,
                          color: _textColor.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                  if (log['sender'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'De: ${log['sender']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _textColor.withOpacity(0.5),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}