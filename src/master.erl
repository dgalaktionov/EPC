%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% master:init().
% master:getImages(URLs). 
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(master).

%% Interface
-export([init/0, getImages/1]).

%% Debug methods
-export([printPendingURLs/0, printProcessedURLs/0, printSlaves/0]).

%% Internal Exports
-export([loop/4, removeDuplicatedURLs/2, removeTrailingSlash/1]).

-define(SLAVE_LIMIT, 50).

-define(PENDING_URLS_LIMIT, 100).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Init
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init() ->
	process_flag(trap_exit, true),
	PID = spawn(master, loop, [[], [], [], 0]),
	register(master, PID).
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Debug utilities
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
printPendingURLs() -> 
	master ! printPendingURLs.
	
printProcessedURLs() -> 
	master ! printProcessedURLs.
	
printSlaves() -> 
	master ! printSlaves.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Tells the master to enqueue new URLs.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
getImages(URLs) ->
	master ! {getImages, URLs}. 


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Removes duplicated URLs from incoming ones
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
removeDuplicatedURLs(URLsToAdd, ProcessedURLs) ->
	[URL || URL <- URLsToAdd, not lists:any(fun(ProcessedURL) -> ProcessedURL == URL end, ProcessedURLs)].
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Removes trailing slashes from URLs
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
removeTrailingSlash(L) ->
	removeTrailingSlash(L, []).
removeTrailingSlash([W | T], Result) ->
	case lists:last(W) of 
		$/ -> removeTrailingSlash(T, [lists:sublist(W, length(W) - 1) | Result]);
		_ -> removeTrailingSlash(T, [W | Result])
		end;
removeTrailingSlash([], Result) ->
	Result.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Creates slaves to crawl URLs if we have available slots
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
assignURLs([], ProcessedURLs, Slaves, _) -> % No new URLs to assign
	{[], ProcessedURLs, Slaves};
	
assignURLs(PendingURLs, ProcessedURLs, Slaves, 0) -> % No Slave slots
	{PendingURLs, ProcessedURLs, Slaves};
	
assignURLs([URL | T], ProcessedURLs, Slaves, SlaveSlots) ->
	SlaveMock = spawn(slaveMock, init, [self(), URL]),
	assignURLs(T, [URL | ProcessedURLs], [SlaveMock | Slaves], SlaveSlots - 1).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Gets URL sublist
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
trim(URLs, Count) when Count =< ?PENDING_URLS_LIMIT ->
	URLs;
	
trim(URLs, _) ->
	lists:sublist(URLs, 1, ?PENDING_URLS_LIMIT).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Pritns list
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
printList([]) -> 
	io:fwrite("End of list~n", []);
printList([H | T]) ->
	io:fwrite("~s~n", [H]),
	printList(T).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Receive messages
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
checkMessages(PendingURLs, ProcessedURLs, Slaves, SlaveCount) ->
	receive
		% Debug messages
        stop ->
            ok;
        printPendingURLs ->
            printList(PendingURLs),
            loop(PendingURLs, ProcessedURLs, Slaves, SlaveCount);
        printProcessedURLs ->
            printList(ProcessedURLs),
            loop(PendingURLs, ProcessedURLs, Slaves, SlaveCount);
        printSlaves ->
            printList(Slaves),
            loop(PendingURLs, ProcessedURLs, Slaves, SlaveCount);
        % Client messages
        {foundURLs, Slave, {CrawledURLs, NewUrls}} -> 
        CrawledURLs_s = removeTrailingSlash(CrawledURLs),
        NewUrls_s = removeTrailingSlash(NewUrls),
        CurrentSlaves = lists:delete(Slave, Slaves),
        UrlsToAdd = removeDuplicatedURLs(NewUrls_s, CrawledURLs_s ++ ProcessedURLs), % Remove duplicated URLs
        loop( UrlsToAdd ++ PendingURLs, CrawledURLs_s ++ ProcessedURLs, CurrentSlaves, SlaveCount - 1);
        {getImages, URLsToAdd} ->
        	URLsToAdd_s = removeTrailingSlash(URLsToAdd),
        	NewURLs = removeDuplicatedURLs(URLsToAdd_s, ProcessedURLs), % Remove duplicated URLs
        	L = NewURLs ++ PendingURLs,
        	CurrentRemaingURLs = trim(L, length(L)), % Trims the URL list to the maximum number of pending URLs
        	loop(CurrentRemaingURLs, ProcessedURLs, Slaves, SlaveCount);
        {'EXIT', _, _} ->
        	io:fwrite("Something wrong has happened", []),
        	exit(self(), error)
    after
        100 ->
            loop(PendingURLs, ProcessedURLs, Slaves, SlaveCount) % Loop forever
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Main loop
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
loop(PendingURLs, ProcessedURLs, Slaves, SlaveCount) when SlaveCount < ?SLAVE_LIMIT ->
	{RemainingURLs, CurrentProcessedURLs, CurrentSlaves} = assignURLs(PendingURLs, ProcessedURLs, Slaves, ?SLAVE_LIMIT - SlaveCount),
	checkMessages(RemainingURLs, CurrentProcessedURLs, CurrentSlaves, length(CurrentSlaves));
	
loop(PendingURLs, ProcessedURLs, Slaves, SlaveCount) ->
	checkMessages(PendingURLs, ProcessedURLs, Slaves, SlaveCount).
		
    

