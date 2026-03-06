-- ==========================================
-- MULTI-SELECT APK INSTALLER
-- Supports: GitHub Pages & CS50/Python HTTP Server
-- ==========================================

local WEB_URL = "https://bookish-computing-machine-g4v964w7xxg739v96-8000.app.github.dev/"

local function get_command_output(cmd)
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    if handle then handle:close() end
    return result
end

local PWD = get_command_output("pwd"):gsub("%s+", "")
local TEMP_APK = PWD .. "/temp_install.apk"
local SAFE_TEMP = "/data/local/tmp/temp_install.apk"

local function split(s, delimiter)
    local result = {}
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

local function url_encode(str)
    str = str:gsub(" ", "%%20")
    str = str:gsub("%(", "%%28")
    str = str:gsub("%)", "%%29")
    return str
end

local function url_decode(str)
    str = str:gsub("%%20", " ")
    str = str:gsub("%%21", "!")
    str = str:gsub("%%28", "(")
    str = str:gsub("%%29", ")")
    str = str:gsub("%%2B", "+")
    str = str:gsub("%%2C", ",")
    str = str:gsub("%%2D", "-")
    str = str:gsub("%%5B", "[")
    str = str:gsub("%%5D", "]")
    str = str:gsub("+", " ")
    return str
end

-- Normalize base URL: pastikan selalu diakhiri "/"
local function normalize_base_url(url)
    if url:sub(-1) ~= "/" then
        return url .. "/"
    end
    return url
end

function main()
    local base_url = normalize_base_url(WEB_URL)
    print("Scanning: " .. base_url)

    local html = get_command_output("curl -sL '" .. base_url .. "'")

    if not html or html == "" then
        print("ERROR: Failed to reach server")
        return
    end

    local apk_files = {}
    local apk_display = {}

    -- ----------------------------------------
    -- STRATEGY 1: Absolute URL (GitHub Pages)
    -- Pattern: href="https://...apk"
    -- ----------------------------------------
    for url in string.gmatch(html, 'href="(https://[^"]+)"') do
        if url:lower():match("%.apk") then
            local filename = url:match("([^/]+)$")
            filename = url_decode(filename)
            table.insert(apk_files, url)
            table.insert(apk_display, filename)
        end
    end

    -- ----------------------------------------
    -- STRATEGY 2: Relative URL (Python http.server / CS50)
    -- Pattern: href="Delta%2064%20...apk"
    -- ----------------------------------------
    if #apk_files == 0 then
        for href in string.gmatch(html, 'href="([^"]+)"') do
            if href:lower():match("%.apk") and not href:match("^http") and not href:match("^/") then
                local filename = url_decode(href)
                local full_url = base_url .. href  -- gunakan href asli (masih encoded) untuk URL
                table.insert(apk_files, full_url)
                table.insert(apk_display, filename)
            end
        end
    end

    -- ----------------------------------------
    -- STRATEGY 3: Absolute path relative URL
    -- Pattern: href="/path/to/file.apk"
    -- ----------------------------------------
    if #apk_files == 0 then
        local domain = base_url:match("(https?://[^/]+)")
        if domain then
            for href in string.gmatch(html, 'href="(/[^"]+)"') do
                if href:lower():match("%.apk") then
                    local filename = href:match("([^/]+)$")
                    filename = url_decode(filename)
                    local full_url = domain .. href
                    table.insert(apk_files, full_url)
                    table.insert(apk_display, filename)
                end
            end
        end
    end

    if #apk_files == 0 then
        print("WARNING: No APK files found!")
        print("DEBUG: First 500 chars of HTML response:")
        print(html:sub(1, 500))
        return
    end

    print("")
    print("========================================")
    print("  APK Installer")
    print("========================================")
    print("")
    print("Available Files:")
    print("----------------------------------------")
    for i, apk in ipairs(apk_display) do
        print("[" .. i .. "] " .. apk)
    end
    print("----------------------------------------")
    print("")

    io.write("Which files? (e.g., '1', '1,3,4', '1-3', 'all'): ")
    local choice = io.read()

    if not choice or choice == "" then
        print("No selection.")
        return
    end

    local selected_indices = {}

    -- Support keyword "all"
    if choice:lower():gsub("%s+", "") == "all" then
        for i = 1, #apk_files do
            selected_indices[i] = true
        end
    else
        for _, part in ipairs(split(choice, ",")) do
            part = part:gsub("%s+", "")
            if part:find("-") then
                local s, e = part:match("(%d+)%-(%d+)")
                if s and e then
                    for i = tonumber(s), tonumber(e) do
                        if i >= 1 and i <= #apk_files then
                            selected_indices[i] = true
                        end
                    end
                end
            elseif tonumber(part) then
                local idx = tonumber(part)
                if idx >= 1 and idx <= #apk_files then
                    selected_indices[idx] = true
                end
            end
        end
    end

    -- Hitung total yang dipilih
    local total_selected = 0
    for _ in pairs(selected_indices) do total_selected = total_selected + 1 end

    if total_selected == 0 then
        print("ERROR: No valid selection.")
        return
    end

    print("")
    print("Starting Process... (" .. total_selected .. " file(s) selected)")
    print("========================================")

    local success_count = 0
    local fail_count = 0

    for i, download_url in ipairs(apk_files) do
        if selected_indices[i] then
            local filename = apk_display[i]
            print("")
            print(">>> [" .. i .. "/" .. #apk_files .. "] " .. filename)
            print("----------------------------------------")
            print("URL: " .. download_url)

            print("[1/2] Downloading...")
            local curl_cmd = string.format('curl -f -# -L -o "%s" "%s"', TEMP_APK, download_url)
            local dl_success = os.execute(curl_cmd)

            if dl_success == true or dl_success == 0 then
                print("[2/2] Installing...")

                os.execute(string.format('su -c \'mv "%s" "%s"\'', TEMP_APK, SAFE_TEMP))
                os.execute(string.format('su -c \'chmod 644 "%s"\'', SAFE_TEMP))

                local install_cmd = string.format('su -c \'pm install -r -d "%s"\'', SAFE_TEMP)
                local inst_success = os.execute(install_cmd)

                if inst_success == true or inst_success == 0 then
                    print("  --> SUCCESS: " .. filename)
                    success_count = success_count + 1
                else
                    print("  --> ERROR: Failed to install")
                    fail_count = fail_count + 1
                end

                os.execute(string.format('su -c \'rm -f "%s"\'', SAFE_TEMP))
            else
                print("  --> ERROR: Failed to download")
                -- Cleanup jika file partial ada
                os.execute(string.format('rm -f "%s"', TEMP_APK))
                fail_count = fail_count + 1
            end
        end
    end

    print("")
    print("========================================")
    print("  SUMMARY")
    print("========================================")
    print("  Success : " .. success_count)
    print("  Failed  : " .. fail_count)
    print("  Total   : " .. total_selected)
    print("========================================")
    print("")
end

main()
