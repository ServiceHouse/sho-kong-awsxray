---
--- Created by ethemcemozkan.
--- DateTime: 29/11/2019 14:07
---

local BasePlugin = require "kong.plugins.base_plugin"

local SHOXrayPlugin = BasePlugin:extend()


SHOXrayPlugin.VERSION  = "1.0.0"
SHOXrayPlugin.PRIORITY = 10

local function isempty(s)
    return s == nil or s == ''
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

function SHOXrayPlugin:new()
    SHOXrayPlugin.super.new(self, "sho-kong-awsxray")
end

function SHOXrayPlugin:access(config)
    SHOXrayPlugin.super.access(self)

    local traceIdHeader = kong.request.get_header("X-Amzn-Trace-Id")
    if not isempty(traceIdHeader) then
        local method =  kong.request.get_method()
        local url = kong.request.get_scheme() .. "://" .. kong.request.get_host() .. kong.request.get_path()
        traceId = traceIdHeader:gsub("Root=", "")
        local startTime = ngx.now()
        local segmentId = tostring(generateId())

        kong.ctx.plugin.segmentDoc = "\"trace_id\":\"" .. traceId .. "\", \"id\": \"" .. segmentId .. "\", \"start_time\": ".. tostring(startTime) .. ", \"name\": \"Kong\""
        kong.ctx.plugin.httpPart = ",\"http\": {\"request\" : { \"url\" : \"".. url .."\", \"method\" : \"".. method .."\"}"
        local inProgress = ",\"in_progress\": true"
        local header = "{\"format\": \"json\", \"version\": 1}"
        local traceData = header .. "\n" .. "{".. kong.ctx.plugin.segmentDoc .. kong.ctx.plugin.httpPart .."}" .. inProgress .. " }"

        ngx.req.set_header("X-Amzn-Trace-Id", traceIdHeader..";Parent="..segmentId..";Sampled=1")
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
        local header = "{\"format\": \"json\", \"version\": 1}"
        local traceData = header .. "\n" .. "{".. kong.ctx.plugin.segmentDoc .. " }"

        ngx.timer.at(0, sendUDP,traceData,config.xray_host,config.xray_port )
    end
end


return SHOXrayPlugin
