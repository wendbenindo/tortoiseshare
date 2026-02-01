import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

class MobileApp extends StatefulWidget {
  const MobileApp({super.key});

  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> {
  Socket? _socket;
  String _status = 'Appuyez sur "Rechercher" pour trouver un PC';
  String _serverIP = '';
  String _pcName = 'PC TortoiseShare';
  bool _isConnected = false;
  bool _isScanning = false;
  bool _scanCompleted = false;
  final TextEditingController _messageController = TextEditingController();
  List<String> _foundServers = [];
  int _scanProgress = 0;
  int _totalScans = 0;

  // Couleurs du thème TortoiseShare
  final Color _primaryColor = const Color(0xFF4CAF50);
  final Color _backgroundColor = const Color(0xFFFAFAFA);
  final Color _cardColor = Colors.white;
  final Color _textColor = const Color(0xFF333333);

  Future<void> _startDiscovery() async {
    if (_isScanning || _isConnected) return;
    
    setState(() {
      _isScanning = true;
      _scanCompleted = false;
      _status = '🔍 Recherche en cours...';
      _foundServers.clear();
      _scanProgress = 0;
      _totalScans = 0;
    });

    // D'abord, détecter notre propre réseau
    String? networkBase = await _detectOwnNetwork();
    
    if (networkBase != null) {
      // Scanner notre réseau COMPLETEMENT
      await _scanNetworkRange(networkBase);
    } else {
      // Scanner les réseaux courants
      await _scanCommonNetworks();
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        _scanCompleted = true;
        
        if (_foundServers.isNotEmpty) {
          _status = '✅ ${_foundServers.length} PC trouvé(s)';
        } else {
          _status = '❌ Aucun PC trouvé';
        }
      });
    }
  }

  Future<String?> _detectOwnNetwork() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.address.startsWith('127.')) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              print('📱 Mon IP: ${addr.address}');
              print('📱 Réseau détecté: ${parts[0]}.${parts[1]}.${parts[2]}');
              return '${parts[0]}.${parts[1]}.${parts[2]}';
            }
          }
        }
      }
    } catch (e) {
      print('Erreur détection réseau: $e');
    }
    return null;
  }

  Future<void> _scanNetworkRange(String networkBase) async {
    // Scanner TOUTES les adresses du réseau (1-254)
    // Mais plus intelligemment : d'abord les adresses courantes, puis le reste
    
    List<int> priorityAddresses = [
      1,    // Routeur
      2,    // Premier appareil
      10,   // Appareils courants
      20,   // Appareils courants
      50,   // Appareils courants
      100,  // Appareils courants
      150,  // Appareils courants
      200,  // Appareils courants
      254   // Dernière adresse
    ];
    
    List<int> allAddresses = List.generate(254, (index) => index + 1);
    
    // Scanner d'abord les adresses prioritaires
    _totalScans = priorityAddresses.length;
    
    for (final i in priorityAddresses) {
      if (!_isScanning) break;
      
      final ip = '$networkBase.$i';
      
      setState(() {
        _scanProgress++;
        _status = 'Scan rapide: $ip';
      });
      
      final found = await _testConnection(ip);
      if (found) {
        return; // Arrêter si on trouve un serveur
      }
      
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    // Si rien trouvé, scanner le reste (mais avec timeout court)
    _totalScans = allAddresses.length;
    
    for (final i in allAddresses) {
      if (!_isScanning) break;
      
      // Ignorer les adresses déjà scannées
      if (priorityAddresses.contains(i)) continue;
      
      final ip = '$networkBase.$i';
      
      setState(() {
        _scanProgress++;
        if (i % 10 == 0) {
          _status = 'Scan complet: $i/254';
        }
      });
      
      final found = await _testConnection(ip);
      if (found) {
        return;
      }
      
      // Pause très courte pour ne pas surcharger
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<bool> _testConnection(String ip) async {
    try {
      print('🔄 Test: $ip:8081');
      final socket = await Socket.connect(
        ip,
        8081,
        timeout: const Duration(milliseconds: 300),
      );
      
      // Tester avec un message hello
      socket.write('MOBILE|HELLO\n');
      await socket.flush();
      
      socket.destroy();
      
      if (mounted && !_foundServers.contains(ip)) {
        setState(() {
          _foundServers.add(ip);
          print('✅ Serveur trouvé: $ip');
        });
      }
      return true;
      
    } catch (e) {
      // Ignorer les erreurs de connexion
      return false;
    }
  }

  Future<void> _scanCommonNetworks() async {
    // Scanner les réseaux les plus courants
    List<String> networks = [
      '192.168.1',    // Le plus commun
      '192.168.0',    // Autre réseau commun
      '192.168.43',   // Hotspot
      '192.168.86',   // Google WiFi
      '10.0.0',       // Réseaux d'entreprise
    ];
    
    List<int> commonAddresses = [1, 2, 10, 20, 50, 100, 254];
    
    _totalScans = networks.length * commonAddresses.length;
    
    for (final network in networks) {
      for (final i in commonAddresses) {
        if (!_isScanning) break;
        
        final ip = '$network.$i';
        
        setState(() {
          _scanProgress++;
          _status = 'Scan réseau $network...';
        });
        
        final found = await _testConnection(ip);
        if (found) {
          return;
        }
        
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> _connectToServer(String ip) async {
    setState(() {
      _status = '🔄 Connexion en cours...';
    });

    try {
      _socket = await Socket.connect(
        ip,
        8081,
        timeout: const Duration(seconds: 3),
      );
      
      _socket!.listen((data) {
        final message = utf8.decode(data).trim();
        _handleServerMessage(message);
      },
      onError: (error) {
        print('❌ Erreur socket: $error');
        _handleConnectionError(error.toString());
      },
      onDone: () {
        print('🔌 Connexion fermée');
        _handleDisconnection();
      });
      
      // Envoyer une demande de connexion
      _socket!.write('MOBILE|CONNECT\n');
      
      setState(() {
        _isConnected = true;
        _serverIP = ip;
        _status = '✅ Connecté au PC';
      });
      
      _showSnackBar('Connexion établie avec succès', Colors.green);
      
    } catch (e) {
      print('❌ Erreur connexion: $e');
      _handleConnectionError(e.toString());
    }
  }

  void _handleServerMessage(String message) {
    print('📨 Serveur: $message');
    
    if (message.startsWith('SERVER|NAME|')) {
      final name = message.substring(12);
      setState(() {
        _pcName = name.isNotEmpty ? name : 'PC TortoiseShare';
      });
      _showSnackBar('Connecté à $_pcName', Colors.green);
    } else if (message.contains('WELCOME')) {
      _showSnackBar('Bienvenue sur TortoiseShare', Colors.blue);
    }
  }

  void _handleConnectionError(String error) {
    if (mounted) {
      setState(() {
        _isConnected = false;
        _status = '❌ Connexion échouée';
      });
      _showSnackBar('Erreur: $error', Colors.red);
    }
  }

  void _handleDisconnection() {
    if (mounted) {
      setState(() {
        _isConnected = false;
        _status = '🔌 Déconnecté';
      });
      _showSnackBar('Déconnecté du PC', Colors.orange);
    }
  }

  Future<void> _sendMessage() async {
    if (_socket == null || !_isConnected || _messageController.text.isEmpty) return;
    
    final message = _messageController.text;
    try {
      _socket!.write('TEXT|$message\n');
      _messageController.clear();
      _showSnackBar('Message envoyé', _primaryColor);
      FocusScope.of(context).unfocus();
    } catch (e) {
      _handleConnectionError(e.toString());
    }
  }

  Future<void> _requestScreenShare() async {
    if (_socket == null || !_isConnected) return;
    
    try {
      _socket!.write('SCREEN|REQUEST\n');
      _showSnackBar('Demande envoyée', Colors.blue);
    } catch (e) {
      _handleConnectionError(e.toString());
    }
  }

  void _disconnect() {
    _socket?.close();
    setState(() {
      _isConnected = false;
      _status = 'Déconnecté';
      _foundServers.clear();
      _scanCompleted = false;
    });
    _showSnackBar('Déconnecté', Colors.orange);
  }

  void _cancelScan() {
    setState(() {
      _isScanning = false;
      _status = 'Scan annulé';
    });
  }

  void _clearResults() {
    setState(() {
      _foundServers.clear();
      _scanCompleted = false;
      _status = 'Appuyez sur "Rechercher" pour trouver un PC';
    });
  }

  void _manualConnect() {
    showDialog(
      context: context,
      builder: (context) {
        String ip = '';
        return AlertDialog(
          title: Text('Connexion manuelle'),
          content: TextField(
            decoration: InputDecoration(
              hintText: '192.168.1.100',
              labelText: 'Adresse IP du PC'
            ),
            onChanged: (value) => ip = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (ip.isNotEmpty) {
                  _connectToServer(ip);
                }
              },
              child: Text('Connecter'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _isScanning = false;
    _socket?.close();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.sensors, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Text(
              'TortoiseShare',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        backgroundColor: _primaryColor,
        elevation: 0,
        actions: [
          if (_isScanning)
            IconButton(
              icon: Icon(Icons.stop, color: Colors.white),
              onPressed: _cancelScan,
              tooltip: 'Arrêter la recherche',
            ),
          if (_scanCompleted && !_isConnected)
            IconButton(
              icon: Icon(Icons.clear_all, color: Colors.white),
              onPressed: _clearResults,
              tooltip: 'Effacer les résultats',
            ),
          IconButton(
            icon: Icon(Icons.settings_ethernet, color: Colors.white),
            onPressed: _manualConnect,
            tooltip: 'Connexion manuelle',
          ),
        ],
      ),
      body: _isConnected ? _buildConnectedUI() : _buildDiscoveryUI(),
    );
  }

  Widget _buildDiscoveryUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.sensors,
                        size: 40,
                        color: _primaryColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'TortoiseShare Mobile',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connexion PC simplifiée',
                      style: TextStyle(
                        fontSize: 14,
                        color: _textColor.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Bouton de recherche principal
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startDiscovery,
                icon: Icon(
                  _isScanning ? Icons.hourglass_top : Icons.search,
                  color: Colors.white,
                ),
                label: Text(
                  _isScanning ? 'Recherche en cours...' : '🔍 Rechercher un PC',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 3,
                  shadowColor: _primaryColor.withOpacity(0.3),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // État et progression
            if (_isScanning || _scanCompleted)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statut',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      if (_isScanning) ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _primaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _status,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _textColor,
                                    ),
                                  ),
                                  if (_totalScans > 0)
                                    Text(
                                      '$_scanProgress/$_totalScans adresses',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _textColor.withOpacity(0.6),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_totalScans > 0) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: _scanProgress / _totalScans,
                            backgroundColor: _backgroundColor,
                            color: _primaryColor,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ] else if (_scanCompleted) ...[
                        Row(
                          children: [
                            Icon(
                              _foundServers.isNotEmpty
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              color: _foundServers.isNotEmpty
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _status,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 20),
            
            // Liste des PC trouvés
            if (_foundServers.isNotEmpty)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'PC DISPONIBLES',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _textColor.withOpacity(0.6),
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '${_foundServers.length} trouvé(s)',
                            style: TextStyle(
                              fontSize: 12,
                              color: _primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      ..._foundServers.map((ip) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _backgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryColor.withOpacity(0.1),
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.desktop_windows,
                                color: _primaryColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'PC TortoiseShare',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _textColor,
                              ),
                            ),
                            subtitle: Text(
                              'IP: $ip\nCliquez pour vous connecter',
                              style: TextStyle(
                                fontSize: 12,
                                color: _textColor.withOpacity(0.5),
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              color: _primaryColor,
                              size: 16,
                            ),
                            onTap: () => _connectToServer(ip),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              )
            else if (_scanCompleted && !_isScanning && _foundServers.isEmpty)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.desktop_access_disabled,
                        size: 60,
                        color: _textColor.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun PC trouvé',
                        style: TextStyle(
                          fontSize: 18,
                          color: _textColor.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Vérifiez que:\n• TortoiseShare Desktop est ouvert\n• Cliquez sur "Autoriser la communication"\n• PC et mobile sont sur le même WiFi\n• Le firewall autorise les connexions\n\nEssayez la connexion manuelle',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _textColor.withOpacity(0.5),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _manualConnect,
                        child: Text('Connexion manuelle'),
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

  Widget _buildConnectedUI() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _primaryColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.desktop_windows,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connecté à',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                          Text(
                            _pcName,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _serverIP,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.link_off, color: Colors.white),
                      onPressed: _disconnect,
                      tooltip: 'Déconnecter',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 12),
                      const SizedBox(width: 8),
                      Text(
                        'Connecté',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Message',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _messageController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Tapez votre message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: _backgroundColor,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _sendMessage,
                          icon: Icon(Icons.send, size: 20),
                          label: Text('Envoyer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                Text(
                  'Actions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 12),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      icon: Icons.screen_share,
                      label: 'Écran',
                      onTap: _requestScreenShare,
                    ),
                    _buildActionButton(
                      icon: Icons.file_upload,
                      label: 'Fichier',
                      onTap: () {
                        _showSnackBar('Transfert fichier à venir', Colors.blue);
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.notifications,
                      label: 'Alerte',
                      onTap: () {
                        _socket?.write('ALERT|PING\n');
                        _showSnackBar('Alerte envoyée', Colors.orange);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: IconButton(
            icon: Icon(icon, color: _primaryColor, size: 28),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: _textColor.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}