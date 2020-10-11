<!--
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
-->

- [English](../../plugins/dynamic-upstream.md)
  
# 目录
  - [目录](#目录)
  - [名字](#名字)
  - [属性](#属性)
  - [如何启用](#如何启用)
  - [测试插件](#测试插件)
  - [禁用插件](#禁用插件)


## 名字
`dynamic-upstream` 对请求进行条件匹配并按比率切分上游。

## 属性

| 参数名        | 类型          | 可选项 | 默认值 | 有效值 | 描述                 |
| ------------ | ------------- | ------ | ------ | ------ | -------------------- |
| rules        | array[object] | 必需  |       |        | 插件的配置列表 |
| match        | array[object] | 必需  |        |        | 匹配规则列表 |
| vars         | 匹配规则 | 可选   |        |        | 由一个或多个{var, operator, val}元素组成的列表，类似这样：{{var, operator, val}, {var, operator, val}, ...}}。例如：{"arg_name", "==", "json"}，表示当前请求参数 name 是 json。这里的 var 与 Nginx 内部自身变量命名是保持一致，所以也可以使用 request_uri、host 等；对于 operator 部分，目前已支持的运算符有 ==、~=、>、< 和 ~~。对于>和<两个运算符，会把结果先转换成 number 然后再做比较。 |
| upstreams    | array[object] | 可选   |        |        | 上游配置规则列表。 |
| upstream_id  | string | 可选   |        |        | 通过上游 id 绑定对应上游。 |
| upstream     | object | 可选   |        |        | 上游配置信息。 |
| type         | string | 可选   |        |        | roundrobin 支持权重的负载，chash 一致性哈希，两者是二选一的。 |
| nodes        | object | 可选   |        |        | 上游节点信息 |
| timeout      | object | 可选   |        |        | 上游超时时间 |
| enable_websocket | boolean | 可选   |        |        | 是否启用 websocket（布尔值），默认不启用。 |
| pass_host    | string | 可选   |        |        | pass 透传客户端请求的 host, node 不透传客户端请求的 host, 使用 upstream node 配置的 host, rewrite 使用 upstream_host 配置的值重写 host 。 |
| upstream_host| string | 可选   |        |        | 只在 pass_host 配置为 rewrite 时有效。 |
| weight       | integer | 可选   |        |        | 根据 weight 值来分配请求的比率。如 weight = 40，说明把40%的请求命中到该上游。 |

## 如何启用

在指定的route上启用 `dynamic-pstream` 插件，动态上游请求。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
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
                                    "127.0.0.1:1981":10
                                }
                            },
                            "weight": 40
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
}'
```

插件设置了请求的匹配规则并绑定端口为`1981`的 upstream，route上默认了端口为`1980`的upstream。

注： 当插件中upstreams中的 `weight` 为100时，默认为蓝绿发布。

## 测试插件

**`match` 校验成功,将40%的请求命中到1981端口的upstream, 60%命中到1980端口的upstream。**

```shell
$ curl http://127.0.0.1:9080/index.html?name=jack -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

match 校验成功，但是命中默认端口为`1980`的 upstream。

```shell
$ curl http://127.0.0.1:9080/index.html?name=jack -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

match 校验成功， 命中端口为`1981`的 upstream。

**缺少请求头 `apisix-key`, match` 校验失败`, 响应都为默认 upstream 的数据 `hello 1980`**
```shell
$ curl http://127.0.0.1:9080/index.html?name=jack -H 'user-id:30' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

## 禁用插件

当你想去掉 dynamic-upstream 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

