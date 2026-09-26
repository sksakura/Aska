# Aska

Минимальное iOS-приложение на SwiftUI: пустой экран со смайликом.

## Локальный запуск (нужен Mac)

```sh
brew install xcodegen
xcodegen generate
open Aska.xcodeproj
```

В Xcode: target **Aska** → **Signing & Capabilities** → включите *Automatically manage signing*
и выберите свою **Team** (подойдёт бесплатный Apple ID). Если bundle id `com.sksakura.aska` занят,
поменяйте его в `project.yml`.

Подключите iPhone кабелем, выберите его сверху в списке устройств и нажмите ▶︎ (Cmd+R).
На телефоне: **Настройки → Конфиденциальность и безопасность → Режим разработчика** → включить (потребует перезагрузку),
а после первой установки — **Настройки → Основные → VPN и управление устройством** → доверять своему Apple ID.

С бесплатным Apple ID сборка работает 7 дней, потом просто запустите её из Xcode ещё раз.

## CI

`.github/workflows/ios-build.yml` собирает неподписанный `Aska-unsigned.ipa` на каждый push
и выкладывает его в артефакты запуска (вкладка Actions).
