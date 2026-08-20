import { ListQuerySessionsResponse, GetQuerySessionResponse, QuerySession } from "@/types/query-session";
import { Query, QueryRequest } from "@/types/query";
import { createApi, fetchBaseQuery } from "@reduxjs/toolkit/query/react";
import { Collection } from "@/types/collection";
import { Agent } from "@/types/agent";
import { createSlice, PayloadAction } from "@reduxjs/toolkit";
import { AuthState } from "./auth";
import { appPath } from "@/lib/app-path";

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
            query: () => ({
                url: '',
                method: 'GET',
                params: {
                    endpoint: '/collections',
                }
            })
        }),
        getAgents: builder.query<{ count: number; limit: number; name: string; start: number; items: Agent[] }, void>({
            query: () => ({
                url: '',
                method: 'GET',
                params: {
                    endpoint: '/agents',
                }
            })
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