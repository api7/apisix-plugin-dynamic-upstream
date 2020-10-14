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
local roundrobin = require("resty.roundrobin")
local re_find  = ngx.re.find
local math     = math

local lrucache_rr_obj = core.lrucache.new({
    ttl = 0, count = 512,
})

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
    },
    default = {{ vars = {{"empty", "==", "empty"}}}}
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
                default = 1,
                minimum = 0,
            }
        }
    },
    minItems = 1,
    maxItems = 20
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


local function generate_random_num(max_val)
    local random_val = math.random(1,max_val)
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
        if not ctx.var[v2[1]] then
            return false
        end

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
    local nodes = upstream_info["nodes"]
    local host_port, weight
    for k, v in pairs(nodes) do     -- TODO: support multiple nodes
        host_port = k
        weight = v
    end

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
        name = upstream_info["name"],
        type = upstream_info["type"],
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


local function new_rr_obj(upstreams)
    local server_list = {}
    for i, upstream_obj in ipairs(upstreams) do
        if not upstream_obj.upstream then
            upstream_obj.upstream = "empty_upstream"
        end
        server_list[upstream_obj.upstream] = upstream_obj.weight
    end

    return roundrobin:new(server_list)
end


function _M.access(conf, ctx)
    local upstreams
    local match_flag
    for _, rule in pairs(conf.rules) do
        match_flag = true
        core.log.info("conf.rules: ", core.json.encode(conf.rules))
        for _, single_match in pairs(rule.match) do
            for _, var in pairs(single_match.vars) do
                -- match is empty
                local l_v, op, r_v = var[1], var[2], var[3]
                if l_v == r_v then
                    break
                end

                -- match is not empty
                local ok = operator_funcs[op](var, ctx)
                core.log.info("ok: ", ok)
                if not ok then
                    core.log.info("match verification failed.")
                    match_flag = false
                    break
                end
            end

            if match_flag then
                break
            end
        end

        if match_flag then
            upstreams = rule.upstreams
            break
        end
    end


    core.log.info("match_flag: ", match_flag)

    if not match_flag then
        return
    end

    local rr_up, err = lrucache_rr_obj(upstreams, nil, new_rr_obj, upstreams)
    if not rr_up then
        core.log.error("lrucache_rr_obj faild: ", err)
        return 500
    end

    local upstream = rr_up:find()
    if upstream and upstream ~= "empty_upstream" then
        core.log.info("upstream: ", core.json.encode(upstream))
        return set_upstream(upstream, ctx)
    end

    return
end


return _M
