---
--- Created by ethemcemozkan.
--- DateTime: 02/12/2019 09:41
---

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "sho-kong-awsxray",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
            {
                xray_host = {
                    type = "string",
                    required = false,
                    default = "127.0.0.1",
                },
            },
            {
                xray_port = {
                    type = "number",
                    required = false,
                    default = 2000,
                },
            }
        }
    }
}