%% @copyright 2012 Opscode, Inc. All Rights Reserved
%% @author Tim Dysinger <timd@opscode.com>
%%
%% Licensed to the Apache Software Foundation (ASF) under one or more
%% contributor license agreements.  See the NOTICE file distributed
%% with this work for additional information regarding copyright
%% ownership.  The ASF licenses this file to you under the Apache
%% License, Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain a copy of
%% the License at http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
%% implied.  See the License for the specific language governing
%% permissions and limitations under the License.

-module(bookshelf_obj).
-include("bookshelf.hrl").
-compile(export_all).

%% ===================================================================
%%                              Cowboy
%% ===================================================================

init(_Transport, _Rq, _Opts) ->
    {upgrade, protocol, cowboy_http_rest}.

%% ===================================================================
%%                         Cowboy HTTP REST
%% ===================================================================

rest_init(Rq, Opts) ->
    {dir, Dir} = lists:keyfind(dir, 1, Opts),
    {ok, ?req(with_amz_request_id, Rq), #state{dir = Dir}}.

allowed_methods(Rq, St) ->
    {['GET'], Rq, St}.

content_types_provided(Rq, St) ->
    {[{{<<"*">>, <<"*">>, []}, download}], Rq, St}.

%% ===================================================================
%%                         Content Accepted
%% ===================================================================

%% ===================================================================
%%                         Content Provided
%% ===================================================================

download(#http_req{host=[Bucket|_], raw_path= <<"/",Path/binary>>}=Rq,
         #state{dir=Dir} = St) ->
    Filename = filename:join([Dir, Bucket, Path]),
    case file:read_file_info(Filename) of
        {ok, #file_info{size=Size}} ->
            {ok, Transport, Socket} = cowboy_http_req:transport(Rq),
            Fun                     = fun() ->
                                              stream(Transport,
                                                     Socket,
                                                     Filename)
                                      end,
            {{stream, Size, Fun}, Rq, St};
        _                           -> {halt, Rq, St}
    end.

stream(Transport, Socket, Filename) ->
    case file:open(Filename, [raw, binary, read_ahead]) of
        {ok, IODevice} -> chunk(Transport, Socket, IODevice);
        E              -> E
    end.

chunk(Transport, Socket, IODevice) ->
    case file:read(IODevice, 4096) of
        eof         -> file:close(IODevice), sent;
        {error, E}  -> {error, E};
        {ok, Chunk} -> Transport:send(Socket, Chunk),
                       chunk(Transport, Socket, IODevice)
    end.