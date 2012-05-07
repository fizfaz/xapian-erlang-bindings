%% This module is a `gen_server' that handles a single port connection.
-module(xapian_drv_tests).
-include_lib("xapian/include/xapian.hrl").
-include_lib("xapian/src/xapian.hrl").

%% Used for testing, then can be moved to an another file
-define(DRV, xapian_drv).

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

testdb_path(Name) -> 
	TestDir = filename:join(code:priv_dir(xapian), test_db),
	file:make_dir(TestDir),
	filename:join(TestDir, Name).


%% This test tries to create a document with all kinds of fields.
simple_test() ->
    % Open test
    Path = testdb_path(simple),
    Params = [write, create, overwrite, 
        #x_value_name{slot = 1, name = slot1}, 
        #x_prefix_name{name = author, prefix = <<$A>>}],
    {ok, Server} = ?DRV:open(Path, Params),
    Document =
        [ #x_stemmer{language = <<"english">>}
        , #x_data{value = "My test data as iolist"} 
        %% It is a term without a position.
        , #x_term{value = "Simple"} 
        %% Posting (a term with a position).
        , #x_term{value = "term", position=1} 
        , #x_value{slot = 0, value = "Slot #0"} 
        , #x_value{slot = slot1, value = "Slot #1"} 
        , #x_text{value = "Paragraph 1"} 
        , #x_delta{}
        , #x_text{value = <<"Paragraph 2">>} 
        , #x_text{value = <<"Michael">>, prefix = author} 
        ],
    DocId = ?DRV:add_document(Server, Document),
    ?assert(is_integer(DocId)),
    Last = ?DRV:last_document_id(Server),
    ?DRV:close(Server),
    Last.

reopen_test() ->
    % Open test
    Path = testdb_path(simple),
    Params = [write, create, overwrite],
    {ok, Server} = ?DRV:open(Path, Params),
    ?DRV:close(Server),

    {ok, ReadOnlyServer} = ?DRV:open(Path, []),
    ?DRV:close(ReadOnlyServer).


-record(stemmer_test_record, {docid, data}).

stemmer_test() ->
    % Open test with the default stemmer
    Path = testdb_path(stemmer),
    Params = [write, create, overwrite, 
        #x_stemmer{language = <<"english">>},
        #x_prefix_name{name = author, prefix = <<$A>>, is_boolean=true}],
    {ok, Server} = ?DRV:open(Path, Params),
    Document =
        [ #x_data{value = "My test data as iolist (NOT INDEXED)"} 
        , #x_text{value = "Return a list of available languages."} 
        , #x_text{value = "And filter it."} 
        , #x_delta{position=300}
        , #x_text{value = "And other string is here."} 
        , #x_text{value = <<"Michael">>, prefix = author} 
        ],
    %% Test a term generator
    DocId = ?DRV:add_document(Server, Document),
    ?assert(is_integer(DocId)),
    Last = ?DRV:last_document_id(Server),

    %% Test a query parser
    Offset = 0,
    PageSize = 10,
    Meta = xapian_record:record(stemmer_test_record, 
        record_info(fields, stemmer_test_record)),

    Q0 = #x_query_string{string="return"},
    Q1 = #x_query_string{string="return AND list"},
    Q2 = #x_query_string{string="author:michael"},
    Q3 = #x_query_string{string="author:olly list"},
    Q4 = #x_query_string{string="author:Michael"},
    Q5 = #x_query_string{string="retur*", features=[default, wildcard]},
    Q6 = #x_query_string{string="other AND Return"},
    Q7 = #x_query_string{string="list NEAR here"},
    Q8 = #x_query_string{string="list NEAR filter"},

    F = fun(Query) ->
        RecList = ?DRV:query_page(Server, Offset, PageSize, Query, Meta),
        io:format(user, "~n~p~n", [RecList]),
        RecList
        end,

    Qs =
    [Q0, Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8],
    [R0, R1, R2, R3, R4, R5, R6, R7, R8] = 
    lists:map(F, Qs),
    ?assertEqual(R7, []),
    ?assertEqual(R8, R0),
    
    ?DRV:close(Server),
    Last.


%% ------------------------------------------------------------------
%% Transations tests
%% ------------------------------------------------------------------

transaction_test_() ->
    % Open test
    Path1 = testdb_path(transaction1),
    Path2 = testdb_path(transaction2),
    Params = [write, create, overwrite],
    {ok, Server1} = ?DRV:open(Path1, Params),
    {ok, Server2} = ?DRV:open(Path2, Params),
    Fun = fun([S1, S2]) ->
        test_result
        end,
    BadFun = fun([S1, S2]) ->
        test_result = 1
        end,
    %% Check fallback
    BadFun2 = fun([S1, S2]) ->
        %% Try to kill S1.
        %% Server1 will be killed because of supervision.
        erlang:exit(S1, hello)
        end,
    %% Check fallback when the transaction process is still alive
    BadFun3 = fun([S1, S2]) ->
        erlang:exit(S1, hello),
        %% Sleep for 1 second.
        %% Because this process is active, then the monitor process will 
        %% kill it, because one of the servers is dead.
        timer:sleep(1000)
        end,
    Result1 = ?DRV:transaction([Server1, Server2], Fun, infinity),
    Result2 = ?DRV:transaction([Server1, Server2], BadFun),
    erlang:unlink(Server1),

    %% Wait for DB closing.
    timer:sleep(1000),
    Result3 = ?DRV:transaction([Server1, Server2], BadFun2),

    %% Server1 was killed. Server2 will replace it.
    {ok, Server3} = ?DRV:open(Path1, Params),
    erlang:unlink(Server2),

    %% 
    timer:sleep(1000),
    Result4 = ?DRV:transaction([Server2, Server3], BadFun3),

    %% Server3 is still alive.
    ?DRV:close(Server3),
    #x_transaction_result{
        is_committed=Committed1,
        is_consistent=Consistent1
    } = Result1,
    #x_transaction_result{
        is_committed=Committed2,
        is_consistent=Consistent2
    } = Result2,
    #x_transaction_result{
        is_committed=Committed3,
        is_consistent=Consistent3
    } = Result3,
    #x_transaction_result{
        is_committed=Committed4,
        is_consistent=Consistent4
    } = Result4,
    {"Check transactions' results for good and bad functions.",
        [ ?_assertEqual(Committed1, true)
        , ?_assertEqual(Consistent1, true)
        , ?_assertEqual(Committed2, false)
        , ?_assertEqual(Consistent2, true)
        , ?_assertEqual(Committed3, false)
        , ?_assertEqual(Consistent3, false)
        , ?_assertEqual(Committed4, false)
        , ?_assertEqual(Consistent4, false)
        , ?_assertEqual(erlang:is_process_alive(Server1), false)
        , ?_assertEqual(erlang:is_process_alive(Server2), false)
        , ?_assertEqual(erlang:is_process_alive(Server3), false)
        ]}.


transaction_readonly_error_test_() ->
    % Open test
    Path = testdb_path(transaction1),
    Params = [],
    {ok, Server} = ?DRV:open(Path, Params),
    Fun = fun([S]) ->
        test_result
        end,
    Result = ?DRV:transaction([Server], Fun, infinity),
    ?DRV:close(Server),
    #x_transaction_result{
        is_committed=Committed,
        is_consistent=Consistent,
        reason=Reason
    } = Result,
    {"Cannot start transaction for readonly server.",
        [ ?_assertEqual(Committed, false)
        , ?_assertEqual(Consistent, true)
        , ?_assertEqual(Reason, readonly_db)
        ]}.
    

    

%% ------------------------------------------------------------------
%% Call C++ tests
%% ------------------------------------------------------------------

-define(DOCUMENT_ID(X), X:32/native-unsigned-integer).
    
%% @doc This test checks the work of `ResultEncoder'.
result_encoder_test() ->
    % Open test
    Path = testdb_path(simple),
    Params = [],
    {ok, Server} = ?DRV:open(Path, Params),
    Reply = ?DRV:internal_run_test(Server, result_encoder, [1, 1000]),
    Reply = ?DRV:internal_run_test(Server, result_encoder, [1, 1000]),
    Reply = ?DRV:internal_run_test(Server, result_encoder, [1, 1000]),
    ?DRV:close(Server),
    ?assertEqual(lists:seq(1, 1000), [ Id || <<?DOCUMENT_ID(Id)>> <= Reply ]),
    ok.
    

%% @doc Check an exception.
exception_test() ->
    Path = testdb_path(simple),
    Params = [],
    {ok, Server} = ?DRV:open(Path, Params),
    % ?assertException(ClassPattern, TermPattern, Expr)
    ?assertException(error, 
        #x_error{type = <<"MemoryAllocationDriverError">>}, 
        ?DRV:internal_run_test(Server, exception, [])),
    ?DRV:close(Server),
    ok.



%% ------------------------------------------------------------------
%% Extracting information
%% ------------------------------------------------------------------

%% The record will contain information about a document.
%% slot1 is a value.
%% docid and data are special fields.
-record(rec_test, {docid, slot1, data}).


read_document_test() ->
    % Open test
    Path = testdb_path(read_document),
    Params = [write, create, overwrite, 
        #x_value_name{slot = 1, name = slot1}],
    {ok, Server} = ?DRV:open(Path, Params),
    Document =
        [ #x_stemmer{language = <<"english">>}
        , #x_data{value = "My test data as iolist"} 
        , #x_value{slot = slot1, value = "Slot #0"} 
        ],
    DocId = ?DRV:add_document(Server, Document),
    Meta = xapian_record:record(rec_test, record_info(fields, rec_test)),
    Rec = ?DRV:read_document(Server, DocId, Meta),
    ?assertEqual(Rec#rec_test.docid, 1),
    ?assertEqual(Rec#rec_test.slot1, <<"Slot #0">>),
    ?assertEqual(Rec#rec_test.data, <<"My test data as iolist">>),
    ?DRV:close(Server).


%% @doc Check an exception.
read_bad_docid_test() ->
    % Open test
    Path = testdb_path(read_document),
    Params = [#x_value_name{slot = 1, name = slot1}],
    {ok, Server} = ?DRV:open(Path, Params),
    Meta = xapian_record:record(rec_test, record_info(fields, rec_test)),
    DocId = 2,
    % ?assertException(ClassPattern, TermPattern, Expr)
    ?assertException(error, 
        #x_error{type = <<"DocNotFoundError">>}, 
        ?DRV:read_document(Server, DocId, Meta)),
    ?DRV:close(Server).


%% ------------------------------------------------------------------
%% Books (query testing)
%% ------------------------------------------------------------------


%% These records are used for tests.
%% They describe values of documents.
-record(book, {docid, author, title, data}).
-record(book_ext, {docid, author, title, data,   rank, weight, percent}).


%% These cases will be runned sequencly.
%% `Server' will be passed as a parameter.
%% `Server' will be opened just once for all cases.
cases_test_() ->
    Cases = 
    [ fun single_term_query_page_case/1
    , fun value_range_query_page_case/1
    , fun double_terms_or_query_page_case/1
    , fun special_fields_query_page_case/1

    , fun enquire_case/1
    , fun resource_cleanup_on_process_down_case/1
    , fun enquire_to_mset_case/1
    , fun qlc_mset_case/1

    , fun create_user_resource_case/1

    %% Advanced enquires
    , fun advanced_enquire_case/1
    , fun advanced_enquire_weight_case/1
    , fun match_set_info_case/1
    ],
    Server = query_page_setup(),
    %% One setup for each test
    {setup, 
        fun() -> Server end, 
        fun query_page_clean/1,
        [Case(Server) || Case <- Cases]}.
    

query_page_setup() ->
    % Open test
	Path = testdb_path(query_page),
    ValueNames = [ #x_value_name{slot = 1, name = author}
                 , #x_value_name{slot = 2, name = title}],
    Params = [write, create, overwrite] ++ ValueNames,
    {ok, Server} = ?DRV:open(Path, Params),
    Base = [#x_stemmer{language = <<"english">>}],
    Document1 = Base ++
        [ #x_data{value = "Non-indexed data here"} 
        , #x_text{value = "erlang/OTP"} 
        , #x_text{value = "concurrency"} 
        , #x_value{slot = title, value = "Software for a Concurrent World"} 
        , #x_value{slot = author, value = "Joe Armstrong"} 
        ],
    Document2 = Base ++
        [ #x_stemmer{language = <<"english">>}
        , #x_text{value = "C++"} 
        , #x_value{slot = title, value = "Code Complete: "
            "A Practical Handbook of Software Construction"} 
        , #x_value{slot = author, value = "Steve McConnell"} 
        ],
    %% Put the documents into the database
    [1, 2] = 
    [ ?DRV:add_document(Server, Document) || Document <- [Document1, Document2] ],
    Server.

query_page_clean(Server) ->
    ?DRV:close(Server).

single_term_query_page_case(Server) ->
    Case = fun() ->
        Offset = 0,
        PageSize = 10,
        Query = "erlang",
        Meta = xapian_record:record(book, record_info(fields, book)),
        RecList = ?DRV:query_page(Server, Offset, PageSize, Query, Meta),
        io:format(user, "~n~p~n", [RecList])
        end,
    {"erlang", Case}.

value_range_query_page_case(Server) ->
    Case = fun() ->
        Offset = 0,
        PageSize = 10,
        Query = #x_query_value_range{slot=author, from="Joe Armstrong", to="Joe Armstrong"},
        Meta = xapian_record:record(book, record_info(fields, book)),
        RecList = ?DRV:query_page(Server, Offset, PageSize, Query, Meta),
        io:format(user, "~n~p~n", [RecList])
        end,
    {"Joe Armstrong - Joe Armstrong", Case}.

double_terms_or_query_page_case(Server) ->
    Case = fun() ->
        Offset = 0,
        PageSize = 10,
        Query = #x_query{op='OR', value=[<<"erlang">>, "c++"]},
        Meta = xapian_record:record(book, record_info(fields, book)),
        RecList = ?DRV:query_page(Server, Offset, PageSize, Query, Meta),
        io:format(user, "~n~p~n", [RecList])
        end,
    {"erlang OR c++", Case}.


%% You can get dynamicly calculated fields.
special_fields_query_page_case(Server) ->
    Case = fun() ->
        Offset = 0,
        PageSize = 10,
        Query = "erlang",
        Meta = xapian_record:record(book_ext, record_info(fields, book_ext)),
        RecList = ?DRV:query_page(Server, Offset, PageSize, Query, Meta),
        io:format(user, "~n~p~n", [RecList])
        end,
    {"erlang (with rank, weight, percent)", Case}.


%% Xapian uses `Xapian::Enquire' class as a hub for making queries.
%% Enquire object can be handled as a resource.
enquire_case(Server) ->
    Case = fun() ->
        Query = "erlang",
        ResourceId = ?DRV:enquire(Server, Query),
        io:format(user, "~n~p~n", [ResourceId]),
        ?DRV:release_resource(Server, ResourceId)
        end,
    {"Simple enquire resource", Case}.


%% If the client is dead, then its resources will be released.
resource_cleanup_on_process_down_case(Server) ->
    Case = fun() ->
        Home = self(),
        Ref = make_ref(),
        spawn_link(fun() ->
                Query = "erlang",
                ResourceId = ?DRV:enquire(Server, Query),
                Home ! {resource_id, Ref, ResourceId}
                end),

        ResourceId = 
        receive
            {resource_id, Ref, ResourceIdI} ->
                ResourceIdI
        end,

        ?assertError(elem_not_found, ?DRV:release_resource(Server, ResourceId))
        end,
    {"Check garbidge collection for resources", Case}.


enquire_to_mset_case(Server) ->
    Case = fun() ->
        Query = "erlang",
        EnquireResourceId = ?DRV:enquire(Server, Query),
        MSetResourceId = ?DRV:match_set(Server, EnquireResourceId),
        io:format(user, "~n ~p ~p~n", [EnquireResourceId, MSetResourceId]),
        ?DRV:release_resource(Server, EnquireResourceId),
        ?DRV:release_resource(Server, MSetResourceId)
        end,
    {"Check conversation", Case}.


%% Tests with QLC.
-include_lib("stdlib/include/qlc.hrl").

qlc_mset_case(Server) ->
    Case = fun() ->
        %% Query is a query to make for retrieving documents from Xapian.
        %% Each document object will be mapped into a document record. 
        %% A document record is a normal erlang record, 
        %% it has structure, described by the user,
        %% using  the `xapian_record:record' call.
        Query = "erlang",
        EnquireResourceId = ?DRV:enquire(Server, Query),
        MSetResourceId = ?DRV:match_set(Server, EnquireResourceId),

        %% Meta is a record, which contains some information about
        %% structure of a document record.
        %% The definition of Meta is incapsulated inside `xapian_record' module.
        Meta = xapian_record:record(book_ext, record_info(fields, book_ext)),

        %% We use internal erlang records for passing information 
        %% beetween `xapian_drv' and `xapian_mset_qlc' modules.
        QlcParams = #internal_qlc_mset_parameters{ record_info = Meta },

        %% internal_qlc_init returns a record, which contains information 
        %% about QlcTable.
        Info = #internal_qlc_info{} = 
        ?DRV:internal_qlc_init(Server, MSetResourceId, QlcParams),
        io:format(user, "~n ~p~n", [Info]),

        %% Create QlcTable from MSet. 
        %% After creation of QlcTable, MSet can be removed.
        Table = xapian_mset_qlc:table(Server, MSetResourceId, Meta),
        ?DRV:release_resource(Server, MSetResourceId),

        %% QueryAll is a list of all matched records.
        QueryAll = qlc:q([X || X <- Table]),

        %% Check `lookup' function. This function is used by `qlc' module.
        %% It will be called to find a record by an index.
        QueryFilter = qlc:q(
            [X || X=#book_ext{docid=DocId} <- Table, DocId =:= 1]),
        Queries = [QueryAll, QueryFilter],

        %% For each query...
        [begin
            %% ... evaluate (execute) ...
            Records = qlc:e(Q),
            %% ... and print out.
            io:format(user, "~n ~p~n", [Records])
            end || Q <- Queries
        ],

        %% This case will cause an error, because DocId > 0.
        QueryBadFilter = qlc:q(
            [X || X=#book_ext{docid=DocId} <- Table, DocId =:= 0]),
        ?assertError(bad_docid, qlc:e(QueryBadFilter))
        end,
    {"Check internal_qlc_init", Case}.


create_user_resource_case(Server) ->
    Case = fun() ->
        %% User-defined resource is an object, which is created on C++ side.
        %% We using Erlang references for returning it back to the user.
        %% A reference can be used only with this Server.
        ResourceId = ?DRV:internal_create_resource(Server, bool_weight),
        io:format(user, "User-defined resource ~p~n", [ResourceId])
        end,
    {"Check creation of user-defined resources", Case}.


%% Additional parameters can be passed to `Xapian::Enquire'.
%% We use `#x_enquire' record for this.
advanced_enquire_case(Server) ->
    Case = fun() ->
        Query = #x_enquire{
            x_query = "Erlang"
        },
        EnquireResourceId = ?DRV:enquire(Server, Query),
        ?assert(is_reference(EnquireResourceId)),
        ?DRV:release_resource(Server, EnquireResourceId)
        end,
    {"Check #x_enquire{}", Case}.


%% We can pass other `Xapian::Weight' object, stored as an user resource.
%% We create new `Xapian::BoolWeight' object as a resource and pass it back
%% as an additional parameter.
advanced_enquire_weight_case(Server) ->
    Case = fun() ->
        Query = #x_enquire{
            x_query = "Erlang",
            weighting_scheme = xapian_resource:bool_weight(Server)
        },
        EnquireResourceId = ?DRV:enquire(Server, Query),
        ?assert(is_reference(EnquireResourceId)),
        ?DRV:release_resource(Server, EnquireResourceId)
        end,
    {"Check #x_enquire{weight=Xapian::BoolWeight}", Case}.


match_set_info_case(Server) ->
    Case = fun() ->
        Query = "erlang",
        EnquireResourceId = ?DRV:enquire(Server, Query),
        ?assert(is_reference(EnquireResourceId)),
        MSetResourceId = ?DRV:match_set(Server, EnquireResourceId),
        Info = 
        ?DRV:mset_info(Server, MSetResourceId, [matches_lower_bound, size]),
        ?DRV:release_resource(Server, EnquireResourceId),
        ?DRV:release_resource(Server, MSetResourceId),
        io:format(user, "~nMSet Info: ~p~n", [Info])
        end,
    {"Check mset_info function.", Case}.

-endif.
