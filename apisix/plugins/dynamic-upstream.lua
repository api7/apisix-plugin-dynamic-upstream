--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core     = require("apisix.core")
local upstream = require("apisix.upstream")
local ngx_re   = require("ngx.re")
local re_find  = ngx.re.find
local math     = math

-- schema of match part
local option_def = {
    {
        type = "array",
        items = {
            {
                type = "string"
            },
            {
                type = "string",
                enum = {
                    "==",
                    "~=",
                    "~~"
                }
            },
            {
                type = "string"
            }
        },
        minItems = 0,
        maxItems = 10
    },
    {
        type = "array",
        items = {
            {
                type = "string",
            },
            {
                type = "string",
                enum = {
                    ">",
                    "<",
                    ">=",
                    "<="
                }
            },
            {
                type = "string",
                pattern = "(^[0-9]+.[0-9]+$|^[0-9]+$)"
            }
        },
        minItems = 0,
        maxItems = 10
    }
}

local match_def = {
    type = "array",
    items = {
        type = "object",
        properties = {
            vars = {
                type = "array",
                items = {
                    anyOf = option_def
                }
            }
        }
    }
}

-- schema of upstreams part
local upstream_def = {
    type = "object",
    additionalProperties = false,
    properties = {
        name = { type = "string" },
        type = {
            type = "string",
            enum = {
                "roundrobin",
                "chash"
            },
            default = "roundrobin"
        },
        nodes = { type = "object" },
        timeout = { type = "object" },
        enable_websocket = { type = "boolean" },
        pass_host = {
            type = "string",
            enum = {
                "pass", "node", "rewrite"
            }
        },
        upstream_host = { type = "string" }
    },
    dependencies = {
        pass_host = {
            anyOf = {
                {
                    properties = {
                        pass_host = { enum = { "rewrite" }}
                    },
                    required = { "upstream_host" }
                },
                {
                    properties = {
                        pass_host = { enum = { "pass", "node" }}
                    },
                }
            }
        }
    }
}

local upstreams_def = {
    type = "array",
    items = {
        type = "object",
        properties = {
            upstream_id = { type = "string" },
            upstream = upstream_def,
            weight = {
                type = "integer",
                minimum = 0,
                maximum = 100
            }
        }
    },
    minItems = 0,
    maxItems = 1
}

local schema = {
    type = "object",
    properties = {
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    match = match_def,
                    upstreams = upstreams_def
                }
            }
        }
    }
}

local plugin_name = "dynamic-upstream"

local _M = {
    version = 0.1,
    priority = 2523,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end


local function generate_random_num()
    local random_val = math.random(1,100)
    return random_val
end


local operator_funcs = {
    ["=="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] == v2[3] then
            return true
        end
        return false
    end,
    ["~="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] ~= v2[3] then
            return true
        end
        return false
    end,
    ["~~"] = function(v2, ctx)
        local from = re_find(ctx.var[v2[1]], v2[3], "jo")
        if from then
            return true
        end
        return false
    end,
    [">"] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] > v2[3] then
            return true
        end
        return false
    end,
    [">="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] >= v2[3] then
            return true
        end
        return false
    end,
    ["<"] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] < v2[3] then
            return true
        end
        return false
    end,
    ["<="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] <= v2[3] then
            return true
        end
        return false
    end
}


local function set_upstream(upstream_info, ctx)
    local upstream_val = upstream_info["upstream"]
    local nodes = upstream_val["nodes"]
    core.log.info("upstream_val['nodes']: ",  
                    core.json.delay_encode(upstream_val["nodes"]))

    local host_port, weight
    for k, v in pairs(nodes) do
        host_port = k
        weight = v
    end
    core.log.info("host_port: ", host_port, " weight: ", weight)

    local host_port_array = ngx_re.split(host_port, ":")
    local host = host_port_array[1]
    local port = host_port_array[2]

    if not port then
        port = 80
    else
        port = tonumber(port)
    end
    core.log.info("host: ", host, " port: ", port)

    local up_conf = {
        name = upstream_val["name"],
        type = upstream_val["type"],
        nodes = {
            {host = host, port = port, weight = weight}
        }
    }

    local ok, err = upstream.check_schema(up_conf)
    if not ok then
        return 500, err
    end

    local matched_route = ctx.matched_route
    upstream.set(ctx, up_conf.type .. "#route_" .. matched_route.value.id,
                ctx.conf_version, up_conf, matched_route)
    return
end


function _M.access(conf, ctx)
    local upstream_info = {}
    local match_flag

    for _, v in pairs(conf.rules) do
        upstream_info = v.upstreams[1]
        for _, v1 in pairs(v.match) do
            match_flag = true
            for _, v2 in pairs(v1.vars) do
                local val = operator_funcs[v2[2]](v2, ctx)
                core.log.info("val: ", val)
                if not val then
                    core.log.info("match check faild.")
                    match_flag = val
                    break
                end
            end
            if match_flag then
                break
            end
        end
    end

    core.log.info("match_flag: ", match_flag)

    if match_flag then
        core.log.info("upstream_info: ", core.json.delay_encode(upstream_info))

        local w = upstream_info["weight"]
        local random_val = generate_random_num()
        core.log.info("random_val: ",random_val ," w: ", w)

        if random_val <= w then
            return set_upstream(upstream_info, ctx)
        end
    end

    return
end


return _M
