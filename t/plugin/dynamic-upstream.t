#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    admin_key: ~
plugins:                          # plugin list
    - dynamic-upstream
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("yaml_config", $yaml_config);
});

run_tests;

__DATA__

=== TEST 1: configure the dynamic-upstream plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "arg_name","==","jack" ]
                                            ]
                                        }
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":20
                                                },
                                                "timeout": {
                                                    "connect": 15,
                                                    "send": 15,
                                                    "read": 15
                                                }
                                            },
                                            "weight": 2
                                        },
                                        {
                                           "upstream": {
                                                "name": "upstream_B",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1982":10
                                                },
                                                "timeout": {
                                                    "connect": 15,
                                                    "send": 15,
                                                    "read": 15
                                                }
                                            },
                                            "weight": 1
                                        },
                                        {
                                            "weight": 1
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: match verification passed and initiated multiple requests
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 8 do
            local _, _, body = t('/server_port?name=jack', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1981, 1981, 1981, 1981, 1982, 1982
--- no_error_log
[error]



=== TEST 3: match verification failed
--- request
GET /server_port?name=james
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 4: add operation of `~~` in vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "arg_name","~~","[a-z]+" ]
                                            ]
                                        }
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":20
                                                }
                                            },
                                            "weight": 2
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: regular check failed, and return 1980 port.
--- request
GET /server_port?name=1234
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 6: allow match configuration to be empty
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":20
                                                }
                                            },
                                            "weight": 1
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: send a request to empty match configuration
--- request
GET /server_port
--- response_body eval
1981
--- no_error_log
[error]



=== TEST 8: node is domain name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "github.com": 0
                                                }
                                            },
                                            "weight": 1
                                        },
                                        {
                                            "weight": 1
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: node is domain name, the request normal(TODO: Error log printing is not allowed). Currently `nodes` is single domain and will print `301` status code.
--- request
GET /hello
--- error_code: 301
--- error_log eval
qr/dns resolver domain: github.com to \d+.\d+.\d+.\d+/
--- no_error_log
[error]



=== TEST 10: operation is `in` or `IN`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "arg_name","in", ["james", "rose"] ],
                                                [ "http_apisix-key","IN", ["hello", "world"] ]
                                            ]
                                        }
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":2
                                                }
                                            },
                                            "weight": 2
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: `var` rule passed, and return plugin port
--- request
GET /server_port?name=james
--- more_headers
apisix-key: world
--- response_body eval
1981
--- no_error_log
[error]



=== TEST 12: `var` rule failed (name value error), and return default port
--- request
GET /server_port?name=jack
--- more_headers
apisix-key: world
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 13: big weight of upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":20
                                                },
                                                "timeout": {
                                                    "connect": 15,
                                                    "send": 15,
                                                    "read": 15
                                                }
                                            },
                                            "weight": 2000
                                        },
                                        {
                                           "upstream": {
                                                "name": "upstream_B",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1982":10
                                                },
                                                "timeout": {
                                                    "connect": 15,
                                                    "send": 15,
                                                    "read": 15
                                                }
                                            },
                                            "weight": 1000
                                        },
                                        {
                                            "weight": 1000
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 14: hit route
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 8 do
            local _, _, body = t('/server_port?name=jack', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1981, 1981, 1981, 1981, 1982, 1982
--- no_error_log
[error]



=== TEST 15: operation is `ip_in` or `IP_IN`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "http_ip-key","ip_in", ["127.0.0.0/10", "10.10.1.1"] ],
                                                [ "http_real-ip","IP_IN", ["192.168.10.1", "10.10.0.0/16"] ] 
                                            ]
                                        }                            
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":2
                                                }
                                            },
                                            "weight": 2
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }                    
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 16: ip_in and IP_IN match passed
--- request
GET /server_port
--- more_headers
ip-key: 127.0.0.1
real-ip: 192.168.10.1
--- response_body eval
1981
--- no_error_log
[error]



=== TEST 17: ip_in or IP_IN match failed( Missing real-ip )
--- request
GET /server_port
--- more_headers
ip-key: 127.0.0.1
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 18: ip_in or IP_IN match failed( real-ip error )
--- request
GET /server_port
--- more_headers
ip-key: 127.0.0.1
real-ip: 192.168.10.2
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 19: ip list is empty
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "http_ip-key","ip_in", [] ]                                               
                                            ]
                                        }                            
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":2
                                                }
                                            },
                                            "weight": 2
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }                    
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 20: ip list is empty, match failed
--- request
GET /server_port
--- more_headers
ip-key: 127.0.0.1
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 21: Use two plugins related to upstream configuration at the same time. (Here is a test from another plugin)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "arg_pageNum","==","aa" ]
                                            ]
                                        }                            
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":50
                                                },
                                                "timeout": {
                                                    "connect": 60000,
                                                    "send": 10000,
                                                    "read": 10000
                                                }
                                            },
                                            "weight": 700
                                        },
                                        {
                                           "upstream": {
                                                "name": "upstream_B",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1982":50
                                                },
                                                "timeout": {
                                                    "connect": 60000,
                                                    "send": 10000,
                                                    "read": 10000
                                                }
                                            },
                                            "weight": 300
                                        }
                                    ]
                                }
                            ]
                        },
                        "gbop-params-rewrite": {
                            "convert": [
                                {
                                    "from": ["QUERY", "name"],
                                    "to": ["PATH", "name"]
                                }
                            ]
                        }
                    },
                    "uri": "/server_port"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 22: When the `params-rewrite` plugin does not configure `new_uri`, the upstream set in the `dynamic-upstream` plugin is valid
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 10 do
            local _, _, body = t('/server_port?pageNum=aa&name=100', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1981, 1981, 1981, 1981, 1981, 1981, 1981, 1982, 1982, 1982
--- no_error_log
[error]



=== TEST 23: `params-rewrite` plugin configuration `new_uri`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "arg_pageNum","==","aa" ]
                                            ]
                                        }                            
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":50
                                                },
                                                "timeout": {
                                                    "connect": 60000,
                                                    "send": 10000,
                                                    "read": 10000
                                                }
                                            },
                                            "weight": 700
                                        },
                                        {
                                           "upstream": {
                                                "name": "upstream_B",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1982":50
                                                },
                                                "timeout": {
                                                    "connect": 60000,
                                                    "send": 10000,
                                                    "read": 10000
                                                }
                                            },
                                            "weight": 300
                                        }
                                    ]
                                }
                            ]
                        },
                        "gbop-params-rewrite": {
                            "new_uri": "/hello",
                            "convert": [
                                {
                                    "from": ["QUERY", "name"],
                                    "to": ["PATH", "name"]
                                }
                            ]
                        }
                    },
                    "uri": "/server_port"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 24: If the `params-rewrite` plugin configures `new_uri`, the upstream set in the `dynamic-upstream` plugin is invalid.
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 10 do
            local _, _, body = t('/server_port?pageNum=aa&name=100', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ""))
    }
}
--- request
GET /t
--- response_body
hello world
hello world
hello world
hello world
hello world
hello world
hello world
hello world
hello world
hello world
--- no_error_log
[error]
