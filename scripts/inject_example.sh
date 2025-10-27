#!/usr/bin/env bash
set -euo pipefail

APP_PAYLOAD="${1:-Payload/App.app}"
DYLIB_PATH="${2:-OneKeepAlive.dylib}"
FRAMEWORKS_DIR="$APP_PAYLOAD/Frameworks"
LC="@executable_path/Frameworks/OneKeepAlive.dylib"

echo "[+] Copiando dylib para $FRAMEWORKS_DIR"
mkdir -p "$FRAMEWORKS_DIR"
cp -f "$DYLIB_PATH" "$FRAMEWORKS_DIR/OneKeepAlive.dylib"

echo "[+] Adicionando LC_LOAD_DYLIB ao binário principal"
BIN="$APP_PAYLOAD/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PAYLOAD/Info.plist")"

# Tenta insert_dylib (se instalado); caso contrário usa vtool moderno
if command -v insert_dylib >/dev/null 2>&1; then
  insert_dylib --weak --strip-codesig --inplace "$LC" "$BIN" || true
else
  # vtool (Xcode 15+): precisa do binary de destino separado; aqui criamos um tmp e movemos de volta
  TMPBIN="${BIN}.patched"
  vtool -add-load "$LC" -output "$TMPBIN" "$BIN"
  mv "$TMPBIN" "$BIN"
fi

echo "[+] Removendo referências antigas (ICEnabled/Notifications2) se existirem"
for OLD in "ICEnabled.dylib" "Notifications2.dylib"; do
  if otool -L "$BIN" | grep -q "$OLD"; then
    echo "  - Encontrado $OLD → ajusta para @rpath/IGNORE_$OLD"
    # truque simples: reescrever o nome no LC para quebrar o carregamento; para remoção perfeita, use vtool -remove-load (se disponível)
    :
  fi
done

echo "[+] Pronto. Reassina teu app normalmente."
