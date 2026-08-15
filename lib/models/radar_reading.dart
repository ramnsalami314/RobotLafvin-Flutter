class RadarReading {
  const RadarReading({
    required this.servoAngle,
    required this.radarAngle,
    required this.distanceCm,
  });

  final int servoAngle;
  final int radarAngle;
  final double distanceCm;
}