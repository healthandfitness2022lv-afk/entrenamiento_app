// lib/services/web_audio.dart
import 'dart:html' as html;

class WebAudio {
  static final Map<String, html.AudioElement> _cache = {};

  static void unlock() {
  html.AudioElement()
    ..src = 'assets/sounds/beep.wav'
    ..volume = 0
    ..play();
}


  static void play(String asset) {
    final audio = _cache.putIfAbsent(
      asset,
      () => html.AudioElement()
        ..src = asset
        ..preload = 'auto',
    );

    audio.currentTime = 0;
    audio.volume = 1;
    audio.play();
  }
}
