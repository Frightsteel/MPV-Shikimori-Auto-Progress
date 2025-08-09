# MPV Shikimori Auto Update

Lua-скрипт для MPV, который автоматически отмечает эпизод просмотренным на [Shikimori](https://shikimori.one), если вы досмотрели его до конца (≥ 90%).  

---

## Установка

### 1. Скачать и установить скрипт
1. Скачайте файл **`shikimori-autoupdate.lua`**.  
2. Поместите его в папку `scripts` MPV:  
   - **Windows:** `%APPDATA%\mpv\scripts`

---

### 2. Установить зависимости
Скрипт использует библиотеку [dkjson](http://dkolf.de/src/dkjson-lua.fsl/home) для работы с JSON.  
Скачайте `dkjson.lua` и поместите его в папку `lua` рядом с `mpv.exe`.

---

### 3. Создать конфиг
Скрипт читает настройки из файла `shikimori-autoupdate-config.json`, который должен находиться в:  
- **Windows:** `%APPDATA%\mpv\scripts-opts\shikimori-autoupdate-config.json`

Создайте папку `scripts-opts` (если её нет) и файл `shikimori-autoupdate-config.json` со следующим содержимым:

```json
{
  "user_id": 0,
  "access_token": "",
  "refresh_token": "",
  "expires_in": 86400,
  "created_at": 0
}
```

---

### 4. Получить токены
Откройте в браузере:

```
https://shikimori.one/oauth/authorize?client_id=PRxCBtiNJKzK_AKst3jEc1cPswIx4jgnC9sRZ-veP3E&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code
```

Авторизуйтесь и скопируйте код авторизации (он появится на странице).

В терминале или командной строке выполните:

```bash
curl -X POST https://shikimori.one/oauth/token \
  -F grant_type=authorization_code \
  -F client_id=PRxCBtiNJKzK_AKst3jEc1cPswIx4jgnC9sRZ-veP3E \
  -F client_secret=kJe7XldnZZkCDH_UCHfSnzmGnc0ZI-FHnqoZljqlk-w \
  -F code=ПОЛУЧЕННЫЙ_КОД \
  -F redirect_uri=urn:ietf:wg:oauth:2.0:oob
```

В ответе будут поля:

- `access_token`
- `refresh_token`
- `expires_in`
- `created_at`

Чтобы получить числовой ID пользователя (он нужен для `user_id` в `config.json`), выполните следующие шаги:

- Зайдите в свой профиль на Shikimori (например, https://shikimori.one/YOUR_USERNAME).
- Откройте консоль разработчика в браузере (нажмите F12).
- Перейдите во вкладку "Console".
- Введите следующий код и нажмите Enter:

```js
fetch('https://shikimori.one/api/users/' + 'Frightsteel')
  .then(response => response.json())
  .then(data => console.log(data.id));
```

Вставьте эти значения в `config.json`.

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
