#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DERIVED="$ROOT/DerivedData"
PRODUCTS="$DERIVED/Build/Products/Release"
APPS="/Applications"
DIST="$ROOT/dist"
VERSION="1.0"
PKG_ID="ru.rudenko.macCalendar.pkg"
PKG_NAME="Календарь РПЛ"
HOST_APP="CalendarHost.app"
AGENT_APP="CalendarAgent.app"

usage() {
  cat <<EOF
Установщик календаря РПЛ для macOS

Использование:
  ./install.sh              собрать и поставить в /Applications
  ./install.sh --pkg        собрать .pkg в папку dist/
  ./install.sh --uninstall  удалить приложения
  ./install.sh --help       эта справка
EOF
}

log() { print -r -- "→ $*"; }

build_apps() {
  log "Собираю CalendarHost (виджет)…"
  xcodebuild -project "$ROOT/CalendarWidget.xcodeproj" \
    -scheme CalendarHost -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" AD_HOC_CODE_SIGNING_ALLOWED=YES \
    -quiet

  log "Собираю CalendarAgent (приложение и трей)…"
  xcodebuild -project "$ROOT/CalendarWidget.xcodeproj" \
    -scheme CalendarAgent -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" AD_HOC_CODE_SIGNING_ALLOWED=YES \
    -quiet

  [[ -d "$PRODUCTS/$HOST_APP" && -d "$PRODUCTS/$AGENT_APP" ]] || {
    print -u2 "Ошибка: не найдены собранные приложения в $PRODUCTS"
    exit 1
  }
}

install_apps() {
  log "Копирую в $APPS…"
  rm -rf "$APPS/$HOST_APP" "$APPS/$AGENT_APP"
  cp -R "$PRODUCTS/$HOST_APP" "$APPS/"
  cp -R "$PRODUCTS/$AGENT_APP" "$APPS/"
  xattr -cr "$APPS/$HOST_APP" "$APPS/$AGENT_APP" 2>/dev/null || true

  log "Запускаю приложения…"
  open "$APPS/$HOST_APP"
  open "$APPS/$AGENT_APP"

  cat <<EOF

Готово.

• Виджет: правый клик по рабочему столу → «Изменить виджеты» → «Календарь».
• Приложение: иконка РПЛ в строке меню, окно календаря уже должно открыться.
• Разрешите доступ к календарям и уведомлениям, если система спросит.
EOF
}

uninstall_apps() {
  log "Останавливаю приложения…"
  osascript -e 'tell application "CalendarAgent" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application "CalendarHost" to quit' >/dev/null 2>&1 || true
  sleep 0.4
  log "Удаляю из $APPS…"
  rm -rf "$APPS/$HOST_APP" "$APPS/$AGENT_APP"
  print "Удалено."
}

make_pkg() {
  local stage="$DIST/payload"
  local scripts="$DIST/scripts"
  local component="$DIST/CalendarRPL-component.pkg"
  local product="$DIST/${PKG_NAME} ${VERSION}.pkg"

  rm -rf "$DIST"
  mkdir -p "$stage" "$scripts"

  cp -R "$PRODUCTS/$HOST_APP" "$stage/"
  cp -R "$PRODUCTS/$AGENT_APP" "$stage/"
  xattr -cr "$stage" 2>/dev/null || true

  cat > "$scripts/postinstall" <<'POST'
#!/bin/bash
set -e
APPS="/Applications"
xattr -cr "$APPS/CalendarHost.app" "$APPS/CalendarAgent.app" 2>/dev/null || true
CONSOLE_USER="$(stat -f '%Su' /dev/console)"
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
  sudo -u "$CONSOLE_USER" open "$APPS/CalendarHost.app" || true
  sudo -u "$CONSOLE_USER" open "$APPS/CalendarAgent.app" || true
fi
exit 0
POST
  chmod 755 "$scripts/postinstall"

  log "Собираю компонент пакета…"
  pkgbuild \
    --root "$stage" \
    --install-location /Applications \
    --scripts "$scripts" \
    --identifier ru.rudenko.macCalendar \
    --version "$VERSION" \
    --ownership recommended \
    "$component"

  cat > "$DIST/Distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>$PKG_NAME</title>
    <organization>ru.rudenko</organization>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <pkg-ref id="ru.rudenko.macCalendar"/>
    <choices-outline>
        <line choice="default">
            <line choice="ru.rudenko.macCalendar"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="ru.rudenko.macCalendar" visible="false">
        <pkg-ref id="ru.rudenko.macCalendar"/>
    </choice>
    <pkg-ref id="ru.rudenko.macCalendar" version="$VERSION" onConclusion="none">CalendarRPL-component.pkg</pkg-ref>
</installer-gui-script>
EOF

  mkdir -p "$DIST/Resources"
  cat > "$DIST/Resources/welcome.html" <<'HTML'
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="utf-8"><style>
  body { font: 13px/1.45 -apple-system, Helvetica, sans-serif; color: #1d1d1f; padding: 12px 8px; }
  h1 { font-size: 18px; margin: 0 0 10px; }
  p { margin: 0 0 8px; }
</style></head>
<body>
  <h1>Календарь РПЛ</h1>
  <p>Установщик положит в «Программы» два приложения:</p>
  <p><b>CalendarHost</b> — контейнер виджета для рабочего стола.</p>
  <p><b>CalendarAgent</b> — календарь, таблица РПЛ и иконка в строке меню.</p>
  <p>После установки разрешите доступ к календарям и уведомлениям.</p>
</body>
</html>
HTML
  cat > "$DIST/Resources/conclusion.html" <<'HTML'
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="utf-8"><style>
  body { font: 13px/1.45 -apple-system, Helvetica, sans-serif; color: #1d1d1f; padding: 12px 8px; }
  h1 { font-size: 18px; margin: 0 0 10px; }
  p { margin: 0 0 8px; }
</style></head>
<body>
  <h1>Готово</h1>
  <p>Приложения запускаются сами.</p>
  <p>Виджет: правый клик по рабочему столу → «Изменить виджеты» → «Календарь».</p>
  <p>Окно календаря и таблица РПЛ — через иконку в строке меню.</p>
</body>
</html>
HTML

  log "Собираю установщик…"
  productbuild \
    --distribution "$DIST/Distribution.xml" \
    --resources "$DIST/Resources" \
    --package-path "$DIST" \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    "$product"

  rm -rf "$stage" "$scripts" "$component" "$DIST/Distribution.xml" "$DIST/Resources"
  log "Пакет: $product"
  open -R "$product"
}

case "${1:-}" in
  --help|-h) usage ;;
  --uninstall) uninstall_apps ;;
  --pkg)
    build_apps
    make_pkg
    ;;
  "")
    build_apps
    install_apps
    ;;
  *)
    print -u2 "Неизвестный аргумент: $1"
    usage
    exit 1
    ;;
esac
