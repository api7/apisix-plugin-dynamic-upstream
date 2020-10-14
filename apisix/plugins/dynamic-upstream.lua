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
local core       = require("apisix.core")
local upstream   = require("apisix.upstream")
local ngx_re     = require("ngx.re")
local roundrobin = require("resty.roundrobin")
local ipmatcher  = require("resty.ipmatcher")
local re_find    = ngx.re.find
local math       = math

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
    default = {{ vars = {{"server_port", ">", "0"}}}}
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
                minimum = 0
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


local operator_funcs = {
<<<<<<< HEAD
    -- var value example: ["http_name", "==", "rose"]
=======
>>>>>>> feat: dynamic-upstream plugin support domain.
    ["=="] = function(var, ctx)
        if ctx.var[var[1]] and ctx.var[var[1]] == var[3] then
            return true
        end
        return false
    end,
    ["~="] = function(var, ctx)
        if ctx.var[var[1]] and ctx.var[var[1]] ~= var[3] then
            return true
        end
        return false
    end,
    ["~~"] = function(var, ctx)
        if not ctx.var[var[1]] then
            return false
        end

        local from = re_find(ctx.var[var[1]], var[3], "jo")
        if from then
            return true
        end
        return false
    end,
    [">"] = function(var, ctx)
        if ctx.var[var[1]] and ctx.var[var[1]] > var[3] then
            return true
        end
        return false
    end,
    [">="] = function(var, ctx)
        if ctx.var[var[1]] and ctx.var[var[1]] >= var[3] then
            return true
        end
        return false
    end,
    ["<"] = function(var, ctx)
        if ctx.var[var[1]] and ctx.var[var[1]] < var[3] then
            return true
        end
        return false
    end,
    ["<="] = function(var, ctx)
        if ctx.var[var[1]] and ctx.var[var[1]] <= var[3] then
            return true
        end
        return false
    end
}


<<<<<<< HEAD
local function set_upstream(upstream_info, ctx)
    local nodes = upstream_info["nodes"]
    local host_port, weight
    for k, v in pairs(nodes) do     -- TODO: support multiple nodes
        host_port = k
        weight    = v
    end

=======
local function split_host_port(host_port)
>>>>>>> feat: dynamic-upstream plugin support domain.
    local host_port_array = ngx_re.split(host_port, ":")
    local host = host_port_array[1]
    local port = host_port_array[2]

    if not port then
        port = 80
    else
        port = tonumber(port)
    end

    core.log.info("host: ", host, " port: ", port)

    return host, port
end


local function parse_domain(host)
    local ip_info, err = core.utils.dns_parse(dns_resolver, host)
    if not ip_info then
        core.log.error("failed to parse domain: ", host, ", error: ",err)
        return nil, err
    end

    core.log.info("parse addr: ", core.json.delay_encode(ip_info))
    core.log.info("resolver: ", core.json.delay_encode(dns_resolver))
    core.log.info("host: ", host)
    if ip_info.address then
        core.log.info("dns resolver domain: ", host, " to ", ip_info.address)
        return ip_info.address
    else
        return nil, "failed to parse domain"
    end
end


local function parse_domain_for_nodes(domain_ip)
    -- TODO: support multiple nodes
    if not ipmatcher.parse_ipv4(domain_ip) and
            not ipmatcher.parse_ipv6(domain_ip) then
        local ip, err = parse_domain(domain_ip)
        if ip then
            return ip
        end

        if err then
            return nil, err
        end
    end

    return domain_ip
end


local function set_upstream(upstream_info, ctx)
    local nodes = upstream_info["nodes"]
    local host_port, weight
    for node_h_p, node_w in pairs(nodes) do    -- TODO: support multiple nodes
        host_port = node_h_p
        weight = node_w
    end

    local domain_ip, port = split_host_port(host_port)
    local host = parse_domain_for_nodes(domain_ip)

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
        for _, single_match in pairs(rule.match) do
            for _, var in pairs(single_match.vars) do
                -- var example: ["http_name", "==", "rose"]
                local op = var[2]
                local ok = operator_funcs[op](var, ctx)
                core.log.info("ok: ", ok)
                if not ok then
                    core.log.info("var comparison result is false.")
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
