---
--- Created by ethemcemozkan.
--- DateTime: 02/12/2019 09:41
---

return {
    no_consumer = true, -- this plugin will only be applied to Services or Routes,
    fields = {
        xray_host = {type = "string", required = false, default = "127.0.0.1"},
        xray_port = {type = "number", required = false, default = 2000},
    },
    self_check = function(schema, plugin_t, dao, is_updating)
        -- perform any custom verification
        return true
    end
}