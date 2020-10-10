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

=== TEST 1: route binding routex plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                [ "arg_name","==","jack" ],
                                                [ "http_api-a",">=","26" ],
                                                [ "http_api-b","~=","hello" ]
                                            ]
                                        },
                                        {
                                            "vars": [
                                                ["arg_user_id", "==", "100"]
                                            ]
                                        },
                                        {
                                            "vars": [
                                                ["http_apisix", "==", "apisix"]
                                            ]
                                        }                       
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                               "name": "upstream_A",
                                               "type": "roundrobin",
                                               "nodes": {
                                                   "127.0.0.1:1981":10
                                               },
                                               "timeout": {
                                                   "connect": 15,
                                                   "send": 15,
                                                   "read": 15
                                               }
                                           },
                                           "weight": 90
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
                    },
                    "uri": "/hello"
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



=== TEST 2: test routex plugin
--- request
GET /hello?name=jack&user_id=100
--- more_headers
api-a: 30
api-b: hello-123
apisix: apisix
--- error_code: 200
--- response_body
hello world
--- no_error_log
[error]
