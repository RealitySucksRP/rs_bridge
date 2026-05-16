RSBridge = RSBridge or {}
RSBridge.Locales = RSBridge.Locales or {}
RSBridge.CurrentLang = RSBridgeConfig.Locale or 'en'

local function loadLanguageFile(resource, lang, namespace)
    local path = ('locales/%s.lua'):format(lang)
    local content = LoadResourceFile(resource, path)
    if not content or content == '' then return false end

    local sandbox = setmetatable({}, { __index = _G })
    local chunk, err = load(content, ('@@%s/%s'):format(resource, path), 't', sandbox)
    if not chunk then
        RSBridge.debug(('Locale parse error %s/%s: %s'):format(resource, path, tostring(err)))
        return false
    end

    local ok, result = pcall(chunk)
    if not ok then
        RSBridge.debug(('Locale exec error %s/%s: %s'):format(resource, path, tostring(result)))
        return false
    end

    if type(result) ~= 'table' then
        RSBridge.debug(('Locale file %s/%s did not return a table'):format(resource, path))
        return false
    end

    RSBridge.Locales[namespace] = RSBridge.Locales[namespace] or {}
    for k, v in pairs(result) do
        RSBridge.Locales[namespace][k] = v
    end

    return true
end

function LoadLocales(resourceName, namespaceOverride)
    resourceName = resourceName or GetCurrentResourceName()
    local namespace = namespaceOverride or resourceName
    local lang = RSBridge.CurrentLang or RSBridgeConfig.Locale or 'en'

    local loaded = loadLanguageFile(resourceName, lang, namespace)
    if not loaded and lang ~= 'en' then
        loaded = loadLanguageFile(resourceName, 'en', namespace)
        if loaded then
            RSBridge.debug(('Locale %s missing for %s, used en fallback'):format(lang, resourceName))
        end
    end

    return loaded
end

function _L(key, ...)
    if type(key) ~= 'string' then return tostring(key) end

    local ns, k
    local dot = string.find(key, '.', 1, true)
    if dot then
        ns = string.sub(key, 1, dot - 1)
        k = string.sub(key, dot + 1)
    else
        ns = 'rs_bridge'
        k = key
    end

    local langTable = RSBridge.Locales[ns]
    local str = langTable and langTable[k] or nil
    if not str then return key end

    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, str, ...)
        if ok then return formatted end
    end

    return str
end

function Translate(key, ...)
    return _L(key, ...)
end

CreateThread(function()
    Wait(50)
    RSBridge.CurrentLang = RSBridgeConfig.Locale or 'en'
    LoadLocales(GetCurrentResourceName(), 'rs_bridge')
    RSBridge.debug(('Locale loaded: %s'):format(RSBridge.CurrentLang))
end)

exports('LoadLocales', LoadLocales)
exports('Translate', Translate)
exports('_L', _L)
