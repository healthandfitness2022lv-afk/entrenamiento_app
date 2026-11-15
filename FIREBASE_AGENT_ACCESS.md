# Acceso local de agente a Firestore

La app Flutter ya usa Firebase cliente. Para que un agente local lea Firestore con permisos administrativos, usa una `service account` separada.

## 1. Crear y guardar credenciales

Descarga un JSON de `service account` desde Firebase o Google Cloud y guárdalo fuera del código fuente, o dentro de `secrets/` si solo será local.

Ejemplo local:

```powershell
New-Item -ItemType Directory -Force .\secrets | Out-Null
```

Luego deja el JSON en:

```text
.\secrets\firebase-admin.service-account.json
```

## 2. Exponer la ruta al agente

En PowerShell:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "$PWD\secrets\firebase-admin.service-account.json"
```

Para persistirla en tu usuario de Windows:

```powershell
[Environment]::SetEnvironmentVariable(
  "GOOGLE_APPLICATION_CREDENTIALS",
  "C:\Users\healt\Desktop\NEXUS\entrenamiento_app\secrets\firebase-admin.service-account.json",
  "User"
)
```

Abre una terminal nueva después de eso.

## 3. Leer Firestore

El repo incluye un script local:

```powershell
.\scripts\Read-Firestore.ps1 -ProjectId entrenamientoapplv -CollectionPath users
```

Leer un documento puntual:

```powershell
.\scripts\Read-Firestore.ps1 -ProjectId entrenamientoapplv -CollectionPath users -DocumentId SOME_UID
```

Leer otra colección:

```powershell
.\scripts\Read-Firestore.ps1 -ProjectId entrenamientoapplv -CollectionPath workouts_logged -PageSize 10
```

## Reiniciar historial de entrenamiento

La utilidad parte siempre en modo de vista previa:

```powershell
node .\scripts\reset-training-history.mjs --projectId entrenamientoapplv
```

Para ejecutar, el nombre del proyecto debe repetirse como confirmación:

```powershell
node .\scripts\reset-training-history.mjs --projectId entrenamientoapplv --execute --confirm entrenamientoapplv
```

Solo elimina `workouts_logged` y las subcolecciones derivadas de logros,
estadísticas y fatiga. Conserva usuarios, ejercicios, rutinas y planificaciones.

## Notas

- Esto usa la API REST de Firestore y firma el token con la `service account`.
- Internamente usa `Node.js`, no el runtime criptográfico de Windows PowerShell.
- No reutiliza el `google-services.json` de Android; ese archivo no sirve para acceso admin.
- Si quieres, en el siguiente paso puedo adaptar el script a tus colecciones reales y dejar consultas más útiles para este proyecto.
