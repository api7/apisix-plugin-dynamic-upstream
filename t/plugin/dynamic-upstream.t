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

=== TEST 1: missing `match` rule
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
                                           "weight": 2
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



=== TEST 2: multiple requests
--- pipelined_requests eval
["GET /server_port?name=jack", "GET /server_port?name=jack", "GET /server_port?name=jack"]
--- more_headers
user-id: 30 
apisix-key: hello
--- response_body eval
["1981", "1981", "1980"]
--- no_error_log
[error]



=== TEST 3: configure `match` rules
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
                                                [ "arg_name","==","jack" ],
                                                [ "http_user-id",">=","23" ],
                                                [ "http_apisix-key","~~","[a-z]+" ]
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



=== TEST 4: match verification passed
--- pipelined_requests eval
["GET /server_port?name=jack", "GET /server_port?name=jack"]
--- more_headers
user-id: 30 
apisix-key: hello
--- response_body eval
["1981", "1981"]
--- no_error_log
[error]



=== TEST 5: match verification failed
--- request
GET /server_port?name=james
--- more_headers
user-id: 30 
apisix-key: hello
--- error_code: 200
--- response_body eval
1980
--- no_error_log
[error]
