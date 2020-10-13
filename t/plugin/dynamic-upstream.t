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



=== TEST 2: initiated multiple requests
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
