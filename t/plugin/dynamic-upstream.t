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



-- TODO: Need to test a valid domain name.
=== TEST 8: node is domain name
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
                                                   "apiseven.com:1981":20
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



=== TEST 8: node is domain name, the request normal
--- request
GET /server_port
--- response_body eval
1980
--- no_error_log
[error]
