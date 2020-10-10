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
local math     = math


local schema = {
    type = "object",
    properties = {
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    match = {
                        type = "array",
                        items = {
                            type = "object",
                            properties = {
                                vars = {
                                    type = "array",
                                    items = {
                                        anyOf = {
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
                                                }
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
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    },
                    upstreams = {
                        type = "array",
                        items = {
                            type = "object",
                            properties = {
                                upstream_id = { type = "string" },
                                upstream = {
                                    type = "object",
                                    additionalProperties = false,
                                    properties = {
                                        name = { type = "string" },
                                        type = {
                                            type = "string",
                                            enum = {
                                                "roundrobin",
                                                "chash"
                                            }
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
                                },
                                weight = {
                                    type = "integer",
                                    minimum = 0,
                                    maximum = 100
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

local plugin_name = "routex"

local _M = {
    version = 0.1,
    priority = 2500,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema
}


local function generate_random_num()
    local random_val = math.random(1,100)
    core.log.info("random-xxx: ", random_val)
    return random_val
end


local operator_funcs = {
    ["=="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] == v2[3] then
            core.log.info("==: ", ctx.var[v2[1]])
            return true
        end
        return false
    end,
    ["~="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] ~= v2[3] then
            core.log.info("~=: ", ctx.var[v2[1]])
            return true
        end
        return false
    end,
    ["~~"] = function(v2, ctx)
        -- todo: regular matching
        if ctx.var[v2[1]] and ctx.var[v2[1]] == v2[3] then
            core.log.info("~~: ", ctx.var[v2[1]])
            return true
        end
        return false
    end,
    [">"] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] > v2[3] then
            core.log.info(">: ", ctx.var[v2[1]])
            return true
        end
        return false
    end,
    [">="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] >= v2[3] then
            core.log.info(">=: ", ctx.var[v2[1]])
            return true
        end
        return false
    end,
    ["<"] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] < v2[3] then
            core.log.info("<: ", ctx.var[v2[1]])
            return true
        end
        return false
    end,
    ["<="] = function(v2, ctx)
        if ctx.var[v2[1]] and ctx.var[v2[1]] <= v2[3] then
            core.log.info("<=: ", ctx.var[v2[1]])
            return true
        end
        return false
    end
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    core.log.info("plugin access phase, conf: ", core.json.encode(conf))

    local upstreams = {}
    local match_flag = true

    if not conf.rules then
        return
    end

    for _, k in pairs(conf.rules) do
        upstreams = k.upstreams
        for _, v in pairs(k.match) do
            if not match_flag then
                break
            end
            for _, v2 in pairs(v.vars) do
                local val = operator_funcs[v2[2]](v2, ctx)
                core.log.info("result: ", val)
                if val == false then
                    core.log.info("match check faild")
                    match_flag = val
                    break
                end
            end
            core.log.info("v--:",core.json.delay_encode(v))
        end
    end


    core.log.info("match_flag: ", match_flag)

    if match_flag then
        core.log.info("upstream-xxx: ", core.json.delay_encode(upstreams))
        -- local ip = conf.rules[1].upstreams[1]["ip"]
        -- local port = conf.rules[1].upstreams[1]["port"]
        local up_conf = {
            type = "roundrobin",
            nodes = {
                {host = "127.0.0.1", port = "1980", weight = 1}
            }
        }

        local ok, err = upstream.check_schema(up_conf)  -- test case has error info
        -- if not ok then
        --     return 500, err
        -- end

        local matched_route = ctx.matched_route
        upstream.set(ctx, up_conf.type .. "#route_" .. matched_route.value.id,
                     ctx.conf_version, up_conf, matched_route)
        return
    end

    return

end


return _M
