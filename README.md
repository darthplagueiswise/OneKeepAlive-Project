# OneKeepAlive – GitHub Actions Build

Esta pasta já vem pronta para tu **comitar direto** no teu repositório e ter a `OneKeepAlive.dylib` compilada em `macos-latest` a cada push (ou manual via `workflow_dispatch`).

## Estrutura
```
.
├─ OneKeepAlive.m
├─ README.md
├─ scripts/
│  └─ inject_example.sh        # exemplo opcional de injeção com vtool/insert_dylib
└─ .github/workflows/
   └─ build-onekeepalive.yml   # workflow pronto
```

## Como usar
1. Cria (ou abre) teu repo e adiciona estes arquivos na raiz.
2. Faz commit/push.
3. Vai em **Actions** do GitHub → _build-onekeepalive_ → pega o artifact **OneKeepAlive-iphoneos** (contém `.dylib` e `.sha256`).

> O workflow compila para **arm64** e tenta **arm64e**; se o runner não suportar arm64e, ele cai pra arm64 automaticamente.

## Compilação local (opcional)
```bash
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
clang -isysroot "$SDK" -fobjc-arc -O2 \
  -arch arm64 -arch arm64e \
  -miphoneos-version-min=12.0 \
  -framework Foundation -framework AVFoundation -framework UIKit \
  -dynamiclib \
  -install_name @rpath/OneKeepAlive.dylib \
  -current_version 1.0 -compatibility_version 1.0 \
  OneKeepAlive.m -o OneKeepAlive.dylib
```

## Injeção (exemplo)
No script `scripts/inject_example.sh` tem um fluxo de referência baseado em `vtool/insert_dylib`.
