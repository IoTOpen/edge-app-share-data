local ev = require("ev")
local http = require("http.request")
local basexx = require("basexx")
local mqtt = require("ev.mqtt")

local edgeEnv = json:readfile("/etc/iot-open/iotopen.json")

local basicAuth = table.concat({ "Basic ", basexx.to_base64(table.concat({ "api-key", ":", cfg.api_key })) })

local targetInstallation
local targetMq

local shouldForward

function connectTargetMqtt()
    local targetEnv = edgeEnv.mqtt_broker:split(":")
    targetMq = mqtt.new(ev, "edge-app-share-" .. app.id)
    targetMq:tls_set(nil, "/etc/ssl/certs")
    targetMq:username_pw_set("api-key", cfg.api_key)
    targetMq:connect(targetEnv[1], tonumber(targetEnv[2]))
end

function fetchTargetInstallation()
    local uri = table.concat({ edgeEnv.api, "/api/v2/installation/", cfg.target_installation })
    local req = http.new_from_uri(uri)
    req.headers:upsert(":method", "GET")
    req.headers:upsert("Authorization", basicAuth)
    local headers, stream = req:go(10)
    if headers:get(":status") ~= "200" then
        error("Unable to fetch installation")
    end
    return json:decode(stream:get_body_as_string())
end

function fetchTargetFunctions()
    local uri = table.concat({ edgeEnv.api, "/api/v2/functionx/", cfg.target_installation, "?app.id=", app.id })
    local req = http.new_from_uri(uri)
    req.headers:upsert(":method", "GET")
    req.headers:upsert("Authorization", basicAuth)
    local headers, stream = req:go(10)
    if headers:get(":status") ~= "200" then
        error("Unable to fetch target functions")
    end
    return json:decode(stream:get_body_as_string())
end

function fetchTargetDevices()
    local uri = table.concat({ edgeEnv.api, "/api/v2/devicex/", cfg.target_installation, "?app.id=", app.id })
    local req = http.new_from_uri(uri)
    req.headers:upsert(":method", "GET")
    req.headers:upsert("Authorization", basicAuth)
    local headers, stream = req:go(10)
    if headers:get(":status") ~= "200" then
        error("Unable to fetch target functions")
    end
    return json:decode(stream:get_body_as_string())
end

function createTargetDevice(d)
    local uri = table.concat({ edgeEnv.api, "/api/v2/devicex/", cfg.target_installation })
    local req = http.new_from_uri(uri)
    req.headers:upsert(":method", "POST")
    req.headers:upsert("Authorization", basicAuth)
    req:set_body(json:encode(d))
    local headers, stream = req:go(10)
    if headers:get(":status") ~= "200" then
        error("Unable to create target device " .. headers:get(":status"))
    end
    return json:decode(stream:get_body_as_string())
end

function createTargetFunction(f)
    local uri = table.concat({ edgeEnv.api, "/api/v2/functionx/", cfg.target_installation })
    local req = http.new_from_uri(uri)
    req.headers:upsert(":method", "POST")
    req.headers:upsert("Authorization", basicAuth)
    req:set_body(json:encode(f))
    local headers, stream = req:go(10)
    if headers:get(":status") ~= "200" then
        error("Unable to create target function")
    end
    return json:decode(stream:get_body_as_string())
end

function generateMirrorDevice(o)
    local new = {
        type = o.type,
        installation_id = targetInstallation.installation,
        meta = o.meta
    }
    new.meta["app.id"] = tostring(app.id)
    new.meta["source.installation"] = tostring(edgeEnv.installation_id)
    new.meta["source.device"] = tostring(o.id)
    return new
end

function generateMirrorFunction(o, deviceId)
    local new = {
        type = o.type,
        installation_id = targetInstallation.installation,
        meta = o.meta
    }
    new.meta["app.id"] = tostring(app.id)
    new.meta["source.installation"] = tostring(edgeEnv.installation_id)
    new.meta["source.function"] = tostring(o.id)
    new.meta["device_id"] = tostring(deviceId)
    return new
end

function handleMessage(topic, payload, retained)
    if retained then
        return
    end
    if targetMq == nil then
        return
    end
    if shouldForward == nil then
        return
    end
    if shouldForward[topic] then
        targetMq:pub(table.concat({ targetInstallation.client_id, topic }, "/"), payload)
    end
end

function sync()
    local newForwardingTable = {}
    local deviceSelection = edge.findDevices(cfg.devices)
    local functionSelection = {}
    for _, device in ipairs(deviceSelection) do
        local testFunctions = edge.findFunctions({ device_id = tostring(device.id) })
        for i, fn in ipairs(testFunctions) do
            table.insert(functionSelection, fn)
            for metaKey, metaValue in pairs(fn.meta) do
                if metaKey:fnmatchex("topic_*") then
                    newForwardingTable[metaValue] = true
                end
            end
        end
    end
    shouldForward = newForwardingTable

    local targetDevices = fetchTargetDevices()
    local targetFunctions = fetchTargetFunctions()

    for _, dev in ipairs(deviceSelection) do
        local remoteDevice = edge.findDevice({ ["source.device"] = tostring(dev.id) }, targetDevices)
        if remoteDevice == nil then
            local newDevice = generateMirrorDevice(dev)
            newDevice = createTargetDevice(newDevice)
            local availableFunctions = edge.findFunctions({ device_id = dev.id })
            for _, fn in ipairs(availableFunctions) do
                local newFunction = generateMirrorFunction(fn, tostring(newDevice.id))
                newFunction = createTargetFunction(newFunction)
            end
        else
            local sourceFunctions = edge.findFunctions({ device_id = tostring(dev.id) })
            local remoteFunctions = edge.findFunctions({ device_id = tostring(remoteDevice.id) }, targetFunctions)

            for _, fn in ipairs(sourceFunctions) do
                local tmpFn = edge.findFunction({ ["source.function"] = tostring(fn.id) }, remoteFunctions)
                if tmpFn == nil then
                    local newFunction = generateMirrorFunction(fn, tostring(remoteDevice.id))
                    newFunction = createTargetFunction(newFunction)
                end
            end
        end
    end
end

function onDevicesUpdated()
    sync()
end

function onFunctionsUpdated()
    sync()
end

function onStart()
    mq:sub("#", 0)
    mq:bind("#", handleMessage)
    targetInstallation = fetchTargetInstallation()
    sync()
    connectTargetMqtt()
end

function onCreate()
end

function onDestroy()
end

function onExit()
end