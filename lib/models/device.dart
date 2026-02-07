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

  // Méthode copyWith pour créer une copie modifiée
  Device copyWith({
    String? id,
    String? name,
    String? ipAddress,
    DeviceType? type,
    DateTime? connectedAt,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      ipAddress: ipAddress ?? this.ipAddress,
      type: type ?? this.type,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }

  // Conversion vers JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ipAddress': ipAddress,
      'type': type.toString(),
      'connectedAt': connectedAt.toIso8601String(),
    };
  }

  // Création depuis JSON
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'],
      name: json['name'],
      ipAddress: json['ipAddress'],
      type: DeviceType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => DeviceType.unknown,
      ),
      connectedAt: DateTime.parse(json['connectedAt']),
    );
  }

  @override
  String toString() => 'Device($name, $ipAddress)';
}

enum DeviceType {
  mobile,
  desktop,
  unknown,
}
