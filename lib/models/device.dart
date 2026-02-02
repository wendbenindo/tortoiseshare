// Modèle représentant un appareil (PC ou Mobile)
class Device {
  final String id;
  final String name;
  final String ipAddress;
  final DeviceType type;
  final DateTime connectedAt;

  Device({
    required this.id,
    required this.name,
    required this.ipAddress,
    required this.type,
    required this.connectedAt,
  });

  @override
  String toString() => 'Device($name, $ipAddress)';
}

enum DeviceType {
  mobile,
  desktop,
  unknown,
}
