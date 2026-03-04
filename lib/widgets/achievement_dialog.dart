import 'package:flutter/material.dart';
import '../models/achievement.dart';

class AchievementDialog extends StatelessWidget {
  final List<Achievement> achievements;

  const AchievementDialog({super.key, required this.achievements});

  static Future<void> show(BuildContext context, List<Achievement> achievements) {
    if (achievements.isEmpty) return Future.value();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AchievementDialog(achievements: achievements),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.emoji_events, color: Colors.amber, size: 30),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "¡Logros Desbloqueados!",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: achievements.map((a) {
            Color catColor = Colors.blue;
            if (a.category == AchievementCategory.strength) catColor = Colors.redAccent;
            if (a.category == AchievementCategory.volume) catColor = Colors.purpleAccent;
            if (a.category == AchievementCategory.intelligence) catColor = Colors.teal;
            if (a.category == AchievementCategory.constancy) catColor = Colors.orange;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.1),
                border: Border.all(color: catColor.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: catColor,
                    foregroundColor: Colors.white,
                    child: Icon(a.icon, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          a.description,
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            elevation: 0,
          ),
          child: const Text("¡Genial!", style: TextStyle(fontWeight: FontWeight.bold)),
        )
      ],
    );
  }
}
