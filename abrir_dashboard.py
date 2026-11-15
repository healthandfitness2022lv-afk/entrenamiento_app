"""
NEXUS — Abrir Panel de Entrenamiento
Ejecuta este script con: python abrir_dashboard.py
"""

import http.server
import socketserver
import webbrowser
import threading
import os
import sys

PORT = 8787
ARCHIVO = "dashboard.html"

# Verificar que el dashboard existe
script_dir = os.path.dirname(os.path.abspath(__file__))
dashboard_path = os.path.join(script_dir, ARCHIVO)

if not os.path.exists(dashboard_path):
    print(f"❌ No se encontró {ARCHIVO} en la misma carpeta que este script.")
    input("Presiona Enter para cerrar...")
    sys.exit(1)

# Cambiar al directorio del script
os.chdir(script_dir)

class SilentHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Silenciar logs

print("=" * 45)
print("  NEXUS — Panel de Entrenamiento")
print("=" * 45)
print(f"\n  Iniciando servidor en puerto {PORT}...")

try:
    with socketserver.TCPServer(("", PORT), SilentHandler) as httpd:
        url = f"http://localhost:{PORT}/{ARCHIVO}"
        print(f"  Abriendo navegador: {url}")
        print("\n  ✅ Servidor activo. Cierra esta ventana")
        print("     para detener el servidor.\n")

        # Abrir navegador después de 1 segundo
        timer = threading.Timer(1.0, lambda: webbrowser.open(url))
        timer.start()

        httpd.serve_forever()

except OSError as e:
    if "Address already in use" in str(e):
        print(f"\n  ⚠️  El puerto {PORT} ya está en uso.")
        print(f"  Prueba abrir directamente: http://localhost:{PORT}/{ARCHIVO}")
        webbrowser.open(f"http://localhost:{PORT}/{ARCHIVO}")
    else:
        print(f"\n  ❌ Error: {e}")
    input("\nPresiona Enter para cerrar...")
