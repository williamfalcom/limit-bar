<p align="center">
  <img src="docs/img/icon-512.png" width="128" alt="icono de limit-bar">
</p>

<h1 align="center">limit-bar</h1>

<p align="center">
  <strong>Los límites de tus suscripciones de IA, en vivo en la barra de menús de macOS.</strong><br>
  Claude Code · Codex · OpenCode Go — un vistazo, ningún bloqueo sorpresa.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <strong>Español</strong>
</p>

---

## Qué hace

limit-bar permanece en silencio en tu barra de menús mostrando cuánto has consumido de la ventana de uso de tus planes de IA. Haz clic en el icono para abrir un panel compacto con una pestaña por cuenta y una barra de progreso por ventana de límite: porcentajes, valores absolutos cuando el proveedor los informa y cuenta regresiva hasta el próximo reinicio.

| Dónde | Qué ves |
| --- | --- |
| Barra de menús | Una barra en vivo **por cuenta**, verde (<70 %), ámbar (70–89 %) o roja (≥90 %); al 100 % el % se convierte en cuenta regresiva |
| Panel (clic) | Pestañas por cuenta/plan, una barra etiquetada por ventana de límite, pie con "actualizado hace…", botón de actualizar y engranaje de Ajustes |

<p align="center">
  <img src="docs/img/menubar.png" width="320" alt="Icono de limit-bar en vivo en la barra de menús"><br>
  <em>El icono en vivo: una barra por cuenta con su propio porcentaje.</em>
</p>

<p align="center">
  <img src="docs/img/panel.png" width="420" alt="Panel de límites de limit-bar"><br>
  <em>El panel: todas las ventanas de la cuenta seleccionada en una pantalla.</em>
</p>

## Proveedores soportados

| Proveedor | Ventanas monitoreadas | Fuente de datos |
| --- | --- | --- |
| **Claude Code** (Pro/Max/Team) | Sesión de 5 horas · Semanal · cubos semanales por modelo (Fable, Opus, …) | Endpoint OAuth de uso de Anthropic; el token se lee localmente del llavero |
| **Codex** (Plus/Pro) | Primaria ~5 horas · secundaria semanal | `codex app-server` JSON-RPC, con respaldo en `$CODEX_HOME/auth.json` |
| **OpenCode Go** | 5 h · semanal · mensual (topes $12/$30/$60) | Esperando una API pública de uso (issues upstream [#10448](https://github.com/anomalyco/opencode/issues/10448), [#18648](https://github.com/anomalyco/opencode/issues/18648)); la pestaña muestra un estado explícito de "aún no disponible" |

## Instalación

**Requisitos:** macOS 14 (Sonoma) o superior.

1. Descarga `limit-bar-v0.1.0.dmg` (o el `.zip`) de la última release.
2. Ábrelo y arrastra **limit-bar.app** a **Aplicaciones**.
3. Inicia limit-bar — su icono aparece en la barra de menús (sin icono en el Dock a propósito).

<p align="center">
  <img src="docs/img/install.png" width="480" alt="Instalando limit-bar desde el DMG"><br>
  <em>Arrastra limit-bar a Aplicaciones.</em>
</p>

> El build distribuido está firmado ad-hoc. En este Mac abre directo; en otros, clic derecho → **Abrir** en el primer arranque para pasar Gatekeeper.

## Primer arranque

1. Haz clic en el icono de la barra de menús → el panel abre en estado vacío.
2. Toca el **engranaje** (o *Agrega tu primera cuenta*) para abrir Ajustes.
3. Agrega cuentas:
   - **Claude Code** — nada que escribir. limit-bar lee el token OAuth que tu CLI de Claude Code ya guardó en el llavero (`Claude Code-credentials`). Cuando macOS pregunte, elige **Permitir siempre**.
   - **Codex** — también automático: los límites vienen de `codex app-server`, usando el inicio de sesión que tu CLI ya tiene.
   - **OpenCode Go** — pega tu clave de API una vez; queda guardada en el llavero.
4. Las cuentas nuevas se consultan de inmediato; después cada cuenta se actualiza con una cadencia conservadora (por defecto **300 s**, configurable 60–3600 s) con backoff exponencial cuando un proveedor responde `429`.

### En el día a día

- Las **barras del icono** reflejan todas las cuentas; seleccionar una pestaña decide qué % aparece junto a ellas.
- **Esc** o hacer clic fuera cierra el panel; el botón ⟳ fuerza una actualización inmediata de todas las cuentas.
- Activa **Iniciar al iniciar sesión** en Ajustes para que el monitoreo sobreviva a los reinicios.
- La interfaz sigue el idioma de macOS (**English**, **Português**, **Español** hoy). También puedes sobrescribirlo por app: Ajustes del Sistema → limit-bar → Idioma.

## Privacidad

Todo permanece en tu máquina. Sin telemetría, sin servicio de cuentas, sin analítica. limit-bar solo habla con los proveedores configurados, reutilizando las credenciales que sus propias CLIs guardan localmente, y consulta endpoints de uso de solo lectura a una cadencia deliberadamente lenta para no perturbar tus cuotas.

## Compilar desde el código fuente

Requisitos: Xcode con `xcodebuild` y [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Cero dependencias externas.

```bash
scripts/build.sh dev          # Build Debug y lanzamiento
scripts/build.sh prod --dmg   # Release .app + .zip + .dmg en dist/
scripts/build.sh test         # Gate completo de pruebas (Swift Testing)
```

La estructura del proyecto se genera desde `project.yml`; ejecuta `xcodegen generate` tras editarlo. El código vive en `Sources/LimitBar/` (App/Core/Providers/UI) y las pruebas en `Tests/LimitBarTests/`.

## Versionado

Fuente única de verdad: el archivo [`VERSION`](VERSION) (semver). Los builds lo inyectan como versión del bundle; el conteo de commits es el número de build. Las releases se etiquetan `v<versión>` — actualmente **v0.1.0**.

---

<div align="center">
  <sub>Hecho para desarrolladores que usan varios planes de IA al mismo tiempo.</sub><br>
  <sub><a href="README.md">English</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <strong>Español</strong></sub>
</div>
