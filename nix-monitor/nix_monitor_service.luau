noctalia.setUpdateInterval(100)

function tr(key)
    return noctalia.tr(key)
end

function cfg(key)
    return noctalia.getConfig(key)
end

function getState(key)
    return noctalia.state.get(key)
end

function setState(key, val)
    noctalia.state.set(key, val)
end

function watchState(key, cb)
    noctalia.state.watch(key, cb)
end

local branch = cfg("branch")
local updateCheckInterval = cfg("check_interval")
local systemStatsCheckInterval = cfg("system_stats_check_interval")
local completedCommands = 0

local localHashCmd  = "nixos-version --hash 2> /dev/null | cut -c -7"
local remoteHashCmd = "git ls-remote https://github.com/NixOS/nixpkgs " .. branch .. " 2>/dev/null | cut -c 1-7"
local nixosGenerationsCmd = "nixos-rebuild list-generations | tail -n +2 | wc -l"
local nixosCurrentGenCmd = "nixos-rebuild list-generations | grep True | awk '{print $1}'"
local hmGenerationsCmd = "home-manager generations | wc -l"
local hmCurrentGenCmd = "home-manager generations | grep '(current)' | awk '{print $5}'"
local storeSizeCmd = `du -s --block-size=1GiB /nix/store | awk '\{print $1 " GiB"\}'`
local closureSizeCmd = "nix path-info --closure-size --human-readable /run/current-system | awk '{print $2, $3}'"

setState("lastCheckTime", 0)
setState("lastCheckTimeStr", "n/a")
setState("localHash", "n/a")
setState("remoteHash", "n/a")
setState("isRunning", false)
setState("isUpdateAvailable", false)
setState("lastSystemStatsCheckTime", 0)
setState("hasHomeManager", noctalia.commandExists("home-manager"))
setState("nixosGenerations", "•••")
setState("nixosCurrentGen", "•••")
setState("hmGenerations", "•••")
setState("hmCurrentGen", "•••")
setState("storeSize", "•••")
setState("closureSize", "•••")

function update()
    if (os.time() - getState("lastCheckTime")) >= 60 * updateCheckInterval then
        checkUpdate()
    end

    if (os.time() - getState("lastSystemStatsCheckTime")) >= 60 * systemStatsCheckInterval then
        checkSystemStats()
    end
end

function checkUpdate()
    if getState("isRunning") then
        return
    end

    setState("lastCheckTime", os.time())
    noctalia.runAsync("date", function(date) setState("lastCheckTimeStr", date.stdout) end)

    if cfg("show_checking_notification") then
        noctalia.notify(tr("notification.checking_update"))
    end

    setState("isRunning", true)

    completedCommands = 0

    noctalia.runAsync(localHashCmd, getLocalHash)
    noctalia.runStream(remoteHashCmd, getRemoteHash)
end

function getLocalHash(result)
    if getState("isRunning") ~= true then
        return
    end

    setState("localHash", result.stdout)
    completedCommands += 1
    onHashCheckCompleted()
end

function getRemoteHash(line)
    if getState("isRunning") ~= true then
        return
    end

    setState("remoteHash", line)
    completedCommands += 1
    onHashCheckCompleted()
end

function onHashCheckCompleted()
    if completedCommands < 2 then
        return
    end

    if getState("localHash") ~= getState("remoteHash") then
        setState("isUpdateAvailable", true)
        if cfg("show_update_notification") then
            noctalia.notify(tr("notification.update_is_available"))
        end
    end

    if cfg("show_checking_notification") then
        noctalia.notify(tr("notification.update_check_completed"))
    end

    setState("isRunning", false)
end

watchState("command", function(command)
    if command == "check" then
        checkUpdate()
    end

    if command == "cancel" then
        noctalia.runAsync(`kill $(ps -ef | grep "git ls-remote https://github.com/NixOS/nixpkgs" | grep -v grep | awk '\{print $2\}')`)
        setState("isRunning", false)
        completedCommands = 0
    end
end)

function checkSystemStats()
    setState("lastSystemStatsCheckTime", os.time())

    noctalia.runAsync(nixosGenerationsCmd, function(result)
        setState("nixosGenerations", result.stdout)
    end)

    noctalia.runAsync(nixosCurrentGenCmd, function(result)
        setState("nixosCurrentGen", result.stdout)
    end)

    if getState("hasHomeManager") then
        noctalia.runAsync(hmGenerationsCmd, function(result)
            setState("hmGenerations", result.stdout)
        end)

        noctalia.runAsync(hmCurrentGenCmd, function(result)
            setState("hmCurrentGen", result.stdout)
        end)
    end

    noctalia.runStream(storeSizeCmd, function(line)
        setState("storeSize", line)
    end)

    noctalia.runStream(closureSizeCmd, function(line)
        setState("closureSize", line)
    end)
end
