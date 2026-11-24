import { ListQuerySessionsResponse, GetQuerySessionResponse, QuerySession } from "@/types/query-session";
import { Query, QueryRequest } from "@/types/query";
import { createApi, fetchBaseQuery, FetchArgs, FetchBaseQueryError, FetchBaseQueryMeta } from "@reduxjs/toolkit/query/react";
import { Collection } from "@/types/collection";
import { Agent } from "@/types/agent";
import { createSlice, PayloadAction } from "@reduxjs/toolkit";
import { AuthState } from "./auth";
import { appPath } from "@/lib/app-path";

interface PagedListResponse<T> {
    count: number;
    limit: number;
    name: string;
    start: number;
    items: T[];
}

// The custom-chat-api GET proxy only forwards the `endpoint` search param, so
// pagination params (limit/start) must be embedded directly in the endpoint
// string rather than passed as separate `params`.
const PAGE_SIZE = 100;

async function fetchAllPages<T>(
    fetchWithBQ: (args: string | FetchArgs) => { data?: unknown; error?: FetchBaseQueryError; meta?: FetchBaseQueryMeta } | PromiseLike<{ data?: unknown; error?: FetchBaseQueryError; meta?: FetchBaseQueryMeta }>,
    path: string,
): Promise<{ data: PagedListResponse<T> } | { error: FetchBaseQueryError }> {
    const items: T[] = [];
    let start = 0;
    let total = Infinity;

    while (start < total) {
        const separator = path.includes('?') ? '&' : '?';
        const result = await Promise.resolve(fetchWithBQ({
            url: '',
            method: 'GET',
            params: {
                endpoint: `${path}${separator}limit=${PAGE_SIZE}&start=${start}`,
            },
        }));

        if (result.error) {
            return { error: result.error };
        }

        const page = result.data as PagedListResponse<T>;
        items.push(...page.items);
        total = page.count;

        // Guard against an unexpected empty page causing an infinite loop.
        if (page.items.length === 0) break;
        start += page.items.length;
    }

    return { data: { count: total, limit: PAGE_SIZE, name: '', start: 0, items } };
}

export interface ChatState {
    sessions: QuerySession[];
    queryMap: { [sessionId: string]: Query[] };
    collections: Collection[];
    agents: Agent[];
}

const initialState: ChatState = {
    sessions: [],
    queryMap: {},
    collections: [],
    agents: [],
}


export const chatApi = createApi({
    reducerPath: 'chatApi',
    tagTypes: ['QuerySession'],
    baseQuery: fetchBaseQuery({
        baseUrl: appPath('/custom-chat-api'),
        prepareHeaders: (headers, { getState }) => {
            const state = getState() as { auth: AuthState };
            const token = state.auth.access_token;
            if (token) {
                headers.set('Authorization', `Bearer ${token}`);
            }
            return headers;
        }
    }),
    endpoints: (builder) => ({
        getSessions: builder.query<ListQuerySessionsResponse, void>({
            query: () => ({
                url: '',
                method: 'GET',
                params: {
                    endpoint: '/querySessions?sortBy=insertTimestamp:descending',
                }
            }),
            providesTags: () => [{ type: 'QuerySession' }]
        }),
        getQuerySession: builder.query<GetQuerySessionResponse, string>({
            query: (sessionId: string) => ({
                url: '',
                method: 'GET',
                params: {
                    endpoint: `/query?filter=eq(querySessionId,${sessionId})`,
                }
            }),
        }),
        sendQuery: builder.mutation<Query, QueryRequest>({
            query: (request: QueryRequest) => ({
                url: '',
                method: 'POST',
                params: {
                    endpoint: '/query',
                    synchronous: 'true',
                    persist: 'true',
                },
                body: request,
            }),
            invalidatesTags: () => [{ type: 'QuerySession' }]
        }),
        getCollections: builder.query<{ count: number; limit: number; name: string; start: number; items: Collection[] }, void>({
            async queryFn(_arg, _api, _extraOptions, fetchWithBQ) {
                return fetchAllPages<Collection>(fetchWithBQ, '/collections');
            },
        }),
        getAgents: builder.query<{ count: number; limit: number; name: string; start: number; items: Agent[] }, void>({
            async queryFn(_arg, _api, _extraOptions, fetchWithBQ) {
                return fetchAllPages<Agent>(fetchWithBQ, '/agents');
            },
        }),
    }),
});

const chatSlice = createSlice({
    name: 'chat',
    initialState: initialState,
    reducers: {},
    extraReducers: (builder) => {
        builder.addMatcher(chatApi.endpoints.getSessions.matchFulfilled, (state, action) => {
            state.sessions = action.payload.items;
        });
        builder.addMatcher(chatApi.endpoints.getCollections.matchFulfilled, (state, action) => {
            state.collections = action.payload.items.sort((a, b) => a.name.localeCompare(b.name));
        });
        builder.addMatcher(chatApi.endpoints.getAgents.matchFulfilled, (state, action) => {
            state.agents = action.payload.items.sort((a, b) => a.name.localeCompare(b.name));
        });
        builder.addMatcher(chatApi.endpoints.getQuerySession.matchFulfilled, (state, action) => {
            state.queryMap[action.payload.sessionId] = action.payload.items;
        });
        builder.addMatcher(chatApi.endpoints.sendQuery.matchFulfilled, (state, action) => {
            if (!state.queryMap[action.payload.querySessionId]) {
                state.queryMap[action.payload.querySessionId] = [];
            }
            state.queryMap[action.payload.querySessionId].push(action.payload);
        });
    }
})

export const { useGetSessionsQuery, useGetQuerySessionQuery, useSendQueryMutation, useGetCollectionsQuery, useGetAgentsQuery } = chatApi;


export default chatSlice.reducer as (state: ChatState, action: PayloadAction) => ChatState;