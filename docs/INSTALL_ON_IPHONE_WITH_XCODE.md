# Установка Luma Beauty ID на iPhone через Xcode

Этот сценарий нужен для локальной установки приложения на личный iPhone без TestFlight.

## Текущий backend

Приложение должно ходить на staging backend:

```text
https://api-staging.lumatestdomen.online
```

В iOS build settings для `BeautyConcierge` должны быть:

```text
API_BASE_URL = https://api-staging.lumatestdomen.online
APP_ENVIRONMENT = staging
```

Картинки товаров загружаются через backend, например:

```text
https://api-staging.lumatestdomen.online/assets/cards/001_FD-BUD-01.png
```

OpenRouter ключ не должен быть в iOS. iOS отправляет запросы только в backend, а backend уже вызывает OpenRouter.

## Где открыть проект

Открывай именно Xcode project:

```text
ios/BeautyConcierge.xcodeproj
```

Scheme:

```text
BeautyConcierge
```

## Bundle Identifier

Для локальной установки через Personal Team используется dev Bundle Identifier:

```text
com.dimalitin.lumabeautyid.dev
```

Если Xcode всё равно ругается на занятый Bundle Identifier, поменяй последнюю часть на уникальную, например:

```text
com.dimalitin.lumabeautyid.dev2
```

## Как установить на iPhone

1. Открой `ios/BeautyConcierge.xcodeproj` в Xcode.
2. Подключи iPhone кабелем к Mac.
3. На iPhone подтверди доверие к компьютеру, если появится запрос.
4. В Xcode сверху рядом со scheme `BeautyConcierge` выбери свой iPhone.
5. Открой project navigator слева.
6. Выбери project `BeautyConcierge`.
7. Выбери target `BeautyConcierge`.
8. Открой вкладку `Signing & Capabilities`.
9. Включи `Automatically manage signing`.
10. В поле `Team` выбери свой Apple ID / `Personal Team`.
11. Проверь `Bundle Identifier`: `com.dimalitin.lumabeautyid.dev`.
12. Нажми `Run` или `Cmd + R`.

Если iPhone попросит включить Developer Mode:

1. Открой на iPhone `Settings`.
2. Перейди в `Privacy & Security`.
3. Открой `Developer Mode`.
4. Включи Developer Mode.
5. Перезагрузи iPhone по запросу.
6. После перезагрузки подтверди включение Developer Mode.
7. Вернись в Xcode и снова нажми `Run`.

Если iPhone пишет про ненадёжного разработчика:

1. Открой `Settings`.
2. Перейди в `General`.
3. Открой `VPN & Device Management`.
4. Выбери профиль разработчика с твоим Apple ID.
5. Нажми `Trust`.
6. Запусти приложение снова.

## Проверка backend прямо с iPhone

Открой в Safari на iPhone:

```text
https://api-staging.lumatestdomen.online/health
```

Открой пример картинки:

```text
https://api-staging.lumatestdomen.online/assets/cards/001_FD-BUD-01.png
```

Если обе ссылки открываются, iPhone видит backend и статические картинки.

## Troubleshooting

### iPhone не виден в Xcode

- Проверь кабель и попробуй другой USB-порт.
- Разблокируй iPhone.
- Подтверди `Trust This Computer` на iPhone.
- Открой Xcode `Window > Devices and Simulators` и проверь, появился ли iPhone.
- Обнови iOS/Xcode, если устройство требует более свежую версию.

### Developer Mode не включён

- Открой на iPhone `Settings > Privacy & Security > Developer Mode`.
- Включи Developer Mode и перезагрузи iPhone.
- После перезагрузки подтверди включение.

### Signing error

- В `Target BeautyConcierge > Signing & Capabilities` включи `Automatically manage signing`.
- Выбери свой Apple ID / `Personal Team`.
- Убедись, что Bundle Identifier уникальный.
- Если Xcode просит, нажми `Register Bundle Identifier`.

### Bundle Identifier already registered

Поставь уникальный dev Bundle Identifier, например:

```text
com.dimalitin.lumabeautyid.dev2
```

После изменения снова нажми `Run`.

### Build failed

- Выбери scheme `BeautyConcierge`.
- Выбери свой iPhone как destination.
- Выполни `Product > Clean Build Folder`.
- Нажми `Run` ещё раз.
- Если ошибка про signing, смотри раздел `Signing error`.

### Приложение установилось, но backend не работает

- Открой на iPhone `https://api-staging.lumatestdomen.online/health`.
- Проверь интернет на iPhone.
- Если health не открывается, проблема в доступности backend/DNS/HTTPS.
- Если health открывается, перезапусти приложение.

### Фото товаров не грузятся

- Открой на iPhone `https://api-staging.lumatestdomen.online/assets/cards/001_FD-BUD-01.png`.
- Если картинка не открывается, проверь static assets на backend.
- Если картинка открывается в Safari, закрой и снова открой приложение.

### Приложение показывает "Сервис временно недоступен"

- Проверь, что build settings содержат `API_BASE_URL = https://api-staging.lumatestdomen.online`.
- Проверь, что `APP_ENVIRONMENT = staging`.
- Убедись, что ты запускаешь свежую сборку после изменения конфигурации.
- Удали приложение с iPhone и нажми `Run` в Xcode заново.

## Manual QA после установки

1. Зарегистрируйся или войди.
2. Создай Beauty ID.
3. Напиши советнику вопрос про уход.
4. Открой подбор.
5. Проверь, что фото товаров загрузились.
6. Добавь товары в корзину.
7. Нажми `Сохранить подборку`.
8. Закрой и снова открой приложение.
9. Проверь, что Beauty ID, чат, корзина и подборка восстановились.
10. Отправь feedback из профиля/настроек.

