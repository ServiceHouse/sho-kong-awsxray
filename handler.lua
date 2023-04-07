---
--- Created by ethemcemozkan.
--- DateTime: 29/11/2019 14:07
---

local SHOXrayPlugin = {
    VERSION  = "3.0.0",
    PRIORITY = 10,
}

local function isempty(s)
    return s == nil or s == ''
end

local function findEnv(url)
    if url:find(".prd.") then
        return "prd"
    elseif url:find(".stg.") then
        return "stg"
    elseif url:find(".tst.") then
        return "tst"
    elseif url:find(".acc.") then
        return "acc"
    end
end

local function findServiceName(url, env)
    serviceName = url:match("[^.]+")
    return serviceName .. "-" .. env
end

local function generateId()
    local random = math.random
    local template ='xxxxxxxxxxxxxxxx'
    math.randomseed(os.time())
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end

function string.toHex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end

local function sendUDP(premature,msg,host,port)
    local socket = ngx.socket.udp
    local udp = assert(socket())
    assert(udp:setpeername(host, port))
    assert(udp:send(msg))
    assert(udp:close())
end

function SHOXrayPlugin:access(config)
    SHOXrayPlugin.super.access(self)

    local traceIdHeader = kong.request.get_header("X-Amzn-Trace-Id")
    if not isempty(traceIdHeader) then
        local method =  kong.request.get_method()
        local host = kong.request.get_host()
        local url = kong.request.get_scheme() .. "://" .. host .. kong.request.get_path()
        local env = findEnv(url)
        local serviceName = findServiceName(host, env)
        local traceId = traceIdHeader:match("Root=(.+)")
        local parentSegmentId = nil
        local parentSegment = nil
        if traceId:find(";Parent=") then
            parentSegmentId = traceId:match("Parent=(.+)")
            if parentSegmentId:find(";") then
                k, l = parentSegmentId:find(";")
                parentSegmentId = parentSegmentId:sub(0,k-1)
            end
            i, j = traceId:find(";Parent=")
            traceId = traceId:sub(0,i-1)
        end

        if not parentSegmentId then
            parentSegmentId = ""
            parentSegment = ""
        else
            parentSegment =  ", \"parent_id\": \"".. parentSegmentId .."\""
        end

        local startTime = ngx.now()
        local segmentId = tostring(generateId())
        local subSegmentId = tostring(generateId())
        kong.ctx.plugin.subSegmentDoc = "\"id\": \"" .. subSegmentId .. "\", \"start_time\": ".. tostring(startTime) .. ", \"name\": \"".. serviceName.."\", \"namespace\": \"remote\""
        kong.ctx.plugin.segmentDoc = "\"trace_id\":\"" .. traceId .. "\", \"id\": \"" .. segmentId .. "\", \"start_time\": ".. tostring(startTime) .. ", \"name\": \"Kong-" .. env .. "\", \"origin\": \"AWS::ECS::Container\"" .. parentSegment
        kong.ctx.plugin.httpPart = ",\"http\": {\"request\" : { \"url\" : \"".. url .."\", \"method\" : \"".. method .."\"}"
        local inProgress = ",\"in_progress\": true"
        local header = "{\"format\": \"json\", \"version\": 1}"
        local traceData = header .. "\n" .. "{".. kong.ctx.plugin.segmentDoc .. kong.ctx.plugin.httpPart .."}, \"subsegments\": [{".. kong.ctx.plugin.subSegmentDoc .. inProgress .."}]" .. inProgress .. " }"

        ngx.req.set_header("X-Amzn-Trace-Id", "Root=" .. traceId..";Parent="..subSegmentId..";Sampled=1")
        sendUDP(false,traceData,config.xray_host,config.xray_port)
    end
end

function SHOXrayPlugin:log(config)
    SHOXrayPlugin.super.log(self)
    local traceIdHeader = kong.request.get_header("X-Amzn-Trace-Id")
    if not isempty(traceIdHeader) then
        local endTime = ngx.now()
        local response = kong.response.get_status()

        kong.ctx.plugin.httpPart = kong.ctx.plugin.httpPart .. ",\"response\" : { \"status\" : ".. response .." }}"
        kong.ctx.plugin.segmentDoc = kong.ctx.plugin.segmentDoc .. ",\"end_time\": " .. tostring(endTime) .. kong.ctx.plugin.httpPart
        kong.ctx.plugin.subSegmentDoc = kong.ctx.plugin.subSegmentDoc .. ",\"end_time\": " .. tostring(endTime)
        local header = "{\"format\": \"json\", \"version\": 1}"
        local traceData = header .. "\n" .. "{".. kong.ctx.plugin.segmentDoc .. ", \"subsegments\": [{".. kong.ctx.plugin.subSegmentDoc .. "}] }"

        ngx.timer.at(0, sendUDP,traceData,config.xray_host,config.xray_port )
    end
end


return SHOXrayPlugin
