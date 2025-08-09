# MPV Shikimori Auto Update

Lua-скрипт для MPV, который автоматически отмечает эпизод просмотренным на [Shikimori](https://shikimori.one), если вы досмотрели его до конца (≥ 90%).  

---

## Установка

### 1. Скачать и установить скрипт
1. Скачайте файл **`shikimori-autoupdate.lua`**.  
2. Поместите его в папку `scripts` MPV:  
   - **Windows:** `%APPDATA%\Roaming\mpv\scripts`

---

### 2. Установить зависимости
Скрипт использует библиотеку [dkjson](http://dkolf.de/src/dkjson-lua.fsl/home) для работы с JSON.  
Скачайте `dkjson.lua` и поместите его в папку `lua` рядом с `mpv.exe`.

---

### 3. Скачать конфиг
Скрипт читает настройки из файла `shikimori-autoupdate-config.json`, который должен находиться в:  
- **Windows:** `%APPDATA%\mpv\scripts-opts\shikimori-autoupdate-config.json`

Создайте папку `scripts-opts` (если её нет) и поместите `shikimori-autoupdate-config.json` в эту папку.

---

### 4. Получить токены
Откройте в браузере:

```
https://shikimori.one/oauth/authorize?client_id=PRxCBtiNJKzK_AKst3jEc1cPswIx4jgnC9sRZ-veP3E&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob&response_type=code&scope=user_rates
```

Авторизуйтесь и скопируйте код авторизации (он появится на странице).

Вставьте этот код в поле "authorization_code" вашего shikimori-autoupdate-config.json.

---

## Как работает

Скрипт отслеживает процент просмотра видеофайла.

Если просмотрено ≥ 90% (PROGRESS_THRESHOLD), скрипт:

- Определяет название аниме и номер серии из имени файла (S01E01, ep01, - 01 и т.д.).
- Находит соответствующее аниме на Shikimori.
- Обновляет ваш прогресс.
- При истечении токена (`access_token`) автоматически запрашивает новый через `refresh_token`.

---

## Примечания

- Аниме должно быть добавлено в ваш список на Shikimori.
- Если формат имени файла необычный, возможно, нужно будет изменить функцию `parse_filename` в скрипте.
- Для Windows путь к `config.json` фиксированный:  
  `%APPDATA%\mpv\scripts-opts\config.json`
