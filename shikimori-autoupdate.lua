local mp = require 'mp'
local utils = require 'mp.utils'

local json = require("dkjson")

local CONFIG_PATH = nil

local TOKEN_EXPIRES_IN = 0
local TOKEN_CREATED_AT = 0

-- Функция чтения shikimori-autoupdate-config.json из папки scripts-opts
local function read_config()
    local appdata = os.getenv("APPDATA")
    if not appdata then
        mp.msg.error("Shikimori: APPDATA environment variable not found")
        return nil
    end

    local sep = package.config:sub(1,1)  -- \ в Windows
    CONFIG_PATH = appdata .. sep .. "mpv" .. sep .. "scripts-opts" .. sep .. "shikimori-autoupdate-config.json"

    local f = io.open(CONFIG_PATH, "r")
    if not f then
        mp.msg.error("Shikimori: shikimori-autoupdate-config.json not found at " .. CONFIG_PATH)
        return nil
    end

    local content = f:read("*a")
    f:close()

    local ok, config = pcall(json.decode, content)
    if not ok or type(config) ~= "table" then
        mp.msg.error("Shikimori: failed to parse shikimori-autoupdate-config.json")
        return nil
    end

    -- Для хранения времени жизни токена и времени создания (если есть)
    TOKEN_EXPIRES_IN = config.expires_in or 0
    TOKEN_CREATED_AT = config.created_at or 0

    return config
end

local config = read_config()
if not config then
    mp.msg.error("Shikimori: invalid config, aborting script")
    return
end

local ACCESS_TOKEN = config.access_token
local REFRESH_TOKEN = config.refresh_token
local USERNAME = config.user_id

local CLIENT_ID = "PRxCBtiNJKzK_AKst3jEc1cPswIx4jgnC9sRZ-veP3E"
local CLIENT_SECRET = "kJe7XldnZZkCDH_UCHfSnzmGnc0ZI-FHnqoZljqlk-w"

local API_URL = "https://shikimori.one/api"
local PROGRESS_THRESHOLD = 0.9

local saved_filename = nil
local saved_working_directory = nil
local last_duration = 0
local last_position = 0

local function save_config()
    if not CONFIG_PATH then return end
    local f, err = io.open(CONFIG_PATH, "w")
    if not f then
        mp.msg.error("Shikimori: failed to open shikimori-autoupdate-config.json for writing: " .. tostring(err))
        return
    end
    local data = {
        user_id = USERNAME,
        access_token = ACCESS_TOKEN,
        refresh_token = REFRESH_TOKEN,
        expires_in = TOKEN_EXPIRES_IN,
        created_at = TOKEN_CREATED_AT
    }
    local content = json.encode(data, { indent = true })
    f:write(content)
    f:close()
    mp.msg.info("Shikimori: shikimori-autoupdate-config.json updated with new tokens")
end

local function get_user_id()
    local args = {
        "curl",
        "-s", "-X", "GET",
        "https://shikimori.one/api/users/whoami",
        "-H", "User-Agent: mpv-shikimori-script",
        "-H", "Authorization: Bearer " .. ACCESS_TOKEN
    }

    local res = utils.subprocess({args = args, cancellable = false})

    if res.status == 0 and res.stdout and #res.stdout > 0 then
        local ok, data = pcall(json.decode, res.stdout)
        if ok and data and data.id then
            return data.id
        else
            mp.msg.error("Shikimori: failed to parse whoami response")
            return nil
        end
    else
        mp.msg.error("Shikimori: whoami request failed with status " .. tostring(res.status))
        return nil
    end
end

local function exchange_authorization_code(code)
    mp.msg.info("Shikimori: exchanging authorization code for tokens...")

    local args = {
        "curl",
        "-s", "-X", "POST",
        "https://shikimori.one/oauth/token",
        "-H", "User-Agent: mpv-shikimori-script",
        "-F", "grant_type=authorization_code",
        "-F", "client_id=" .. CLIENT_ID,
        "-F", "client_secret=" .. CLIENT_SECRET,
        "-F", "code=" .. code,
        "-F", "redirect_uri=urn:ietf:wg:oauth:2.0:oob"
    }

    local res = utils.subprocess({args = args, cancellable = false})

    if res.status == 0 and res.stdout and #res.stdout > 0 then
        local ok, data = pcall(json.decode, res.stdout)
        if ok and data and data.access_token and data.refresh_token and data.expires_in and data.created_at then
            ACCESS_TOKEN = data.access_token
            REFRESH_TOKEN = data.refresh_token
            TOKEN_EXPIRES_IN = data.expires_in
            TOKEN_CREATED_AT = data.created_at

            local user_id = get_user_id()
            if user_id then
                USERNAME = user_id
                save_config()
                mp.msg.info("Shikimori: authorization code exchanged successfully, user ID fetched and saved.")
                return true
            else
                mp.msg.error("Shikimori: failed to get user ID after authorization")
                return false
            end
        else
            mp.msg.error("Shikimori: failed to parse token response")
            mp.msg.error("Response: " .. tostring(res.stdout))
            return false
        end
    else
        mp.msg.error("Shikimori: authorization code exchange request failed with status " .. tostring(res.status))
        return false
    end
end

local function is_token_expired()
    if TOKEN_EXPIRES_IN == 0 or TOKEN_CREATED_AT == 0 then
        -- Нет данных о времени жизни, считаем что токен не просрочен
        return false
    end
    local current_time = os.time()
    local expire_time = TOKEN_CREATED_AT + TOKEN_EXPIRES_IN - 60  -- минус 60 секунд для буфера
    return current_time >= expire_time
end

local function refresh_access_token()
    mp.msg.info("Shikimori: refreshing access token...")

    local args = {
        "curl",
        "-s", "-X", "POST",
        "https://shikimori.one/oauth/token",
        "-H", "User-Agent: mpv-shikimori-script",
        "-F", "grant_type=refresh_token",
        "-F", "client_id=" .. CLIENT_ID,
        "-F", "client_secret=" .. CLIENT_SECRET,
        "-F", "refresh_token=" .. REFRESH_TOKEN
    }

    local res = utils.subprocess({ args = args, cancellable = false })

    if res.status == 0 and res.stdout and #res.stdout > 0 then
        local ok, data = pcall(json.decode, res.stdout)
        if ok and data and data.access_token and data.refresh_token and data.expires_in and data.created_at then
            ACCESS_TOKEN = data.access_token
            REFRESH_TOKEN = data.refresh_token
            TOKEN_EXPIRES_IN = data.expires_in
            TOKEN_CREATED_AT = data.created_at
            save_config()
            mp.msg.info("Shikimori: access token refreshed successfully.")
            return true
        else
            mp.msg.error("Shikimori: failed to parse token refresh response")
            mp.msg.error("Response: " .. tostring(res.stdout))
            return false
        end
    else
        mp.msg.error("Shikimori: token refresh request failed with status " .. tostring(res.status))
        return false
    end
end

local function encode_url(str)
    if (str) then
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^%w%-_.~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    end
    return str
end

local function ensure_token_valid()
    if is_token_expired() then
        mp.msg.info("Shikimori: access token expired, refreshing...")
        if not refresh_access_token() then
            mp.msg.error("Shikimori: failed to refresh expired token")
        end
    end
end

local function run_curl(method, url, body)
    ensure_token_valid()

    local args = {
        "curl",
        "-s", "--request", method,
        "-H", "Authorization: Bearer " .. ACCESS_TOKEN,
        "-H", "Content-Type: application/json",
        url
    }
    if body then
        table.insert(args, "-d")
        table.insert(args, body)
    end

    local result = utils.subprocess({args = args, cancellable = false})

    -- При 401 (curl возвращает 22 для HTTP ошибки) попробуем обновить токен и повторить
    if result.status == 22 then
        mp.msg.info("Shikimori: Unauthorized (401), refreshing token and retrying...")
        if refresh_access_token() then
            -- Повторяем запрос с новым токеном
            args[5] = "Authorization: Bearer " .. ACCESS_TOKEN
            result = utils.subprocess({args = args, cancellable = false})
        end
    end

    return result.status, result.stdout
end

local function parse_filename(path)
    local filename = path:match("[^\\/]+$")
    if not filename then return nil, nil end

    -- Попытка 0: формат S01E01
    local name, season, ep = string.match(filename, "(.+)[ ._%-]S(%d%d)E(%d%d)")
    if name and season and ep then
        name = name:gsub("[_.%-]", " "):lower()
        return name:match("^%s*(.-)%s*$"), tonumber(ep)
    end

    -- Попытка 1: формат с ep (ep08, e08)
    name, ep = string.match(filename, "(.+)[ _%-]ep?0*([0-9]+)")
    if name and ep then
        name = name:gsub("[_.%-]", " "):lower()
        return name:match("^%s*(.-)%s*$"), tonumber(ep)
    end

    -- Попытка 2: формат с просто дефисом и номером (например, " - 08")
    name, ep = string.match(filename, "(.+)%s*%-[%s]*0*([0-9]+)")
    if name and ep then
        name = name:gsub("[_.%-]", " "):lower()
        return name:match("^%s*(.-)%s*$"), tonumber(ep)
    end

    -- Попытка 3: просто пробел и номер в конце перед расширением
    name, ep = string.match(filename, "(.+)%s0*([0-9]+)%..+$")
    if name and ep then
        name = name:gsub("[_.%-]", " "):lower()
        return name:match("^%s*(.-)%s*$"), tonumber(ep)
    end

    return nil, nil
end


local function find_anime(query)
    local url = API_URL .. "/animes?search=" .. encode_url(query)
    local code, body = run_curl("GET", url)
    if code == 0 and body and #body > 0 then
        local ok, result = pcall(json.decode, body)
        if ok and result and #result > 0 then
            return result[1]
        end
    end
    return nil
end

local function find_user_rate(anime_id)
    local url = API_URL .. "/v2/user_rates?user_id=" .. USERNAME .. "&target_id=" .. anime_id .. "&target_type=Anime"
    local code, body = run_curl("GET", url)
    if code == 0 and body and #body > 0 then
        local ok, result = pcall(json.decode, body)
        if ok and result and #result > 0 then
            return result[1]
        end
    end
    return nil
end

local function update_progress(user_rate_id, episode)
    local url = API_URL .. "/v2/user_rates/" .. user_rate_id
    local body = json.encode({episodes = episode})
    local code, response = run_curl("PUT", url, body)
    mp.msg.info("Shikimori update response code:", code)
    mp.msg.info("Shikimori update response body:", response)
end

local function mark_episode_watched(anime_name, episode)
    local anime = find_anime(anime_name)
    if not anime then
        mp.msg.info("Shikimori: Anime not found:", anime_name)
        return
    end
    mp.msg.info("Shikimori: Found anime:", anime.russian or anime.name)

    local rate = find_user_rate(anime.id)
    if not rate then
        mp.msg.info("Shikimori: Anime not in your list, add it first on site.")
        return
    end

    if not rate.episodes then
        mp.msg.info("Shikimori: No episodes watched info available for this anime.")
        return
    end

    if episode > rate.episodes then
        mp.msg.info("Shikimori: Updating watched episodes to", episode)
        update_progress(rate.id, episode)
    else
        mp.msg.info("Shikimori: Nothing to update, already watched", rate.episodes)
    end
end

mp.register_event("file-loaded", function()
    last_duration = mp.get_property_number("duration", 0)
    saved_filename = mp.get_property("filename")
    saved_working_directory = mp.get_property("working-directory")
end)

mp.observe_property("time-pos", "number", function(name, value)
    if value then
        last_position = value
    end
end)

mp.register_event("end-file", function()
    mp.msg.info("Shikimori: end-file event triggered")

    if last_duration < 60 then
        mp.msg.info("Shikimori: file too short, ignoring")
        return
    end

    local percent_watched = last_position / last_duration
    mp.msg.info(string.format("Shikimori: watched %.2f%% (%d / %d seconds)", percent_watched * 100, last_position, last_duration))

    if percent_watched < PROGRESS_THRESHOLD then
        mp.msg.info("Shikimori: watched less than threshold, not marking as watched")
        return
    end

    local anime_name, episode = parse_filename(saved_filename or "")
    if not anime_name or not episode then
        mp.msg.info("Shikimori: failed to parse anime name or episode from filename")
        return
    end

    mark_episode_watched(anime_name, episode)
end)

-- Проверяем токен при старте скрипта
if config.authorization_code and (not ACCESS_TOKEN or ACCESS_TOKEN == "") and (not REFRESH_TOKEN or REFRESH_TOKEN == "") then
    -- Первый заход, есть код, но нет токенов
    if not exchange_authorization_code(config.authorization_code) then
        mp.msg.error("Shikimori: failed to exchange authorization code")
        return
    end
else
    if is_token_expired() then
        refresh_access_token()
    end
end

