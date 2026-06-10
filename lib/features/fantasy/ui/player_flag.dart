import 'package:flutter/material.dart';

/// Runde Nationalflagge eines Spielers (flagcdn). [code] ist ein
/// ISO-Ländercode wie 'de' oder 'gb-eng'.
class PlayerFlag extends StatelessWidget {
  const PlayerFlag({super.key, required this.code, this.size = 26});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.network(
          'https://flagcdn.com/w80/$code.png',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Text(code.toUpperCase().substring(0, 2),
                style: const TextStyle(fontSize: 9)),
          ),
        ),
      ),
    );
  }
}
