import 'package:shared_preferences/shared_preferences.dart';

class AthleteSelectionService {
  static const String _idKey = 'selected_athlete_id';
  static const String _nameKey = 'selected_athlete_name';

  static Future<void> save(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, id);
    await prefs.setString(_nameKey, name);
  }

  static Future<Map<String, String?>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    final name = prefs.getString(_nameKey);
    if (id == null) return null;
    return {'id': id, 'name': name};
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_nameKey);
  }
}
